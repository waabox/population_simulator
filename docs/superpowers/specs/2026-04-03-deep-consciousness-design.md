# Deep Consciousness — Design Spec

## Overview

Five new layers of consciousness on top of the existing system (autobiographical memory, café conversations, introspection):

1. **Intentions with agency** — Actors generate free-form intentions during introspection, the LLM resolves them, and profile_effects are applied (employment changes, buying dollars, etc.)
2. **Emergent social bonds** — Actors who share 3+ cafés form persistent relationships. CafeGrouper prioritizes seating bonded actors together. Bonds decay without reinforcement.
3. **Cognitive dissonance** — Mathematical index measuring contradiction between mood/beliefs/history and decisions. High dissonance increases LLM temperature (volatility) and triggers confrontation during introspection.
4. **Personal life events** — ~20% of actors per measure receive LLM-generated events (measure-derived or life events). Events modify mood and profile, decaying over time.
5. **Theory of mind** — After each café, actors form a perception of their group's mood and identify 1-2 referents who influenced them. These perceptions shape future decisions.

## Simulation Cycle

```
=== MEASURE N ===

1. MeasureRunner
   → 1000 decisions (prompt includes consciousness + active events + perceptions)
   → temperature adjusted by actor's dissonance index

2. DissonanceCalculator
   → compute dissonance per actor (mood vs decision vs history)
   → persist in decision.dissonance field
   → accumulated unresolved dissonance → +0.5 social_anger

3. EventGenerator
   → select ~200 actors weighted by vulnerability
   → LLM generates personalized event per actor
   → apply mood_impact + profile_effects
   → decay previous events (duration - 1)

4. CafeRunner
   → CafeGrouper prioritizes seating bonded actors together
   → prompt includes bond info between participants
   → LLM generates conversation + effects + referents

5. AffinityTracker
   → increment shared_cafes for each pair in each table
   → form bond when shared_cafes >= 3
   → decay inactive bonds

6. TheoryOfMindBuilder
   → compute group mood from café data (no LLM)
   → persist referents from café output
   → update actor perceptions

=== EVERY 3 MEASURES ===

7. IntrospectionRunner
   → prompt includes: pending intentions + dissonances + perceptions
   → LLM generates: narrative + self_observations + new intentions
   → LLM resolves prior intentions (executed/frustrated)
   → LLM confronts accumulated dissonances

8. IntentionExecutor
   → apply profile_effects from executed intentions
   → mark expired intentions older than 2 introspections
```

## Cost

| Component | Calls/measure | Notes |
|-----------|--------------|-------|
| Decisions | 1000 | existing |
| Events | ~200 | new, ~20% of actors |
| Cafés | ~150 | existing |
| Introspection | ~333 (amortized) | existing, every 3 measures |
| **Total** | **~1350/measure** | +17% over current |

Per 3-measure cycle: ~5050 calls (+13% over current 4450).

## Data Model

### `actor_intentions`

| Column | Type | Description |
|--------|------|-------------|
| `id` | UUID | PK |
| `actor_id` | UUID | FK to actors |
| `measure_id` | UUID | FK to measures (when generated) |
| `description` | TEXT | Free-form intention text from LLM |
| `profile_effects` | TEXT | JSON map of profile field changes |
| `urgency` | STRING | "high", "medium", "low" |
| `status` | STRING | "pending", "executed", "frustrated", "expired" |
| `resolved_at` | DATETIME | nullable |
| `inserted_at` | DATETIME | |

Max 2 active intentions per actor. Oldest pending expires after 2 introspections.

### `actor_bonds`

| Column | Type | Description |
|--------|------|-------------|
| `id` | UUID | PK |
| `actor_a_id` | UUID | FK to actors (always a < b for uniqueness) |
| `actor_b_id` | UUID | FK to actors |
| `affinity` | FLOAT | 0.0 to 1.0 |
| `shared_cafes` | INTEGER | count of cafés shared |
| `formed_at` | DATETIME | nullable, set when shared_cafes >= 3 |
| `last_cafe_at` | DATETIME | |
| `inserted_at` | DATETIME | |
| `updated_at` | DATETIME | |

Unique index on `(actor_a_id, actor_b_id)`. Max 10 bonds per actor. Affinity decays -0.1 per measure without shared café. Bond deleted at affinity 0.

### `actor_events`

| Column | Type | Description |
|--------|------|-------------|
| `id` | UUID | PK |
| `actor_id` | UUID | FK to actors |
| `measure_id` | UUID | FK to measures |
| `description` | TEXT | Event narrative from LLM |
| `mood_impact` | TEXT | JSON map of mood dimension changes |
| `profile_effects` | TEXT | JSON map of profile field changes |
| `duration` | INTEGER | total measures of effect (1-6) |
| `remaining` | INTEGER | measures left |
| `active` | BOOLEAN | false when remaining = 0 |
| `inserted_at` | DATETIME | |

Max 3 active events per actor. Oldest replaced if exceeded.

### `actor_perceptions`

| Column | Type | Description |
|--------|------|-------------|
| `id` | UUID | PK |
| `actor_id` | UUID | FK to actors |
| `measure_id` | UUID | FK to measures |
| `cafe_session_id` | UUID | FK to cafe_sessions |
| `group_mood` | TEXT | JSON: {mood, agreement_ratio, dominant_emotion} |
| `referent_id` | UUID | FK to actors, nullable |
| `referent_influence` | TEXT | what the referent made them think |
| `inserted_at` | DATETIME | |

### Modified table: `decisions`

Add column: `dissonance` (FLOAT, nullable, 0.0-1.0)

## Layer 1: Intentions

### Generation

During introspection, the LLM output extends with:

```json
{
  "narrative": "...",
  "self_observations": ["..."],
  "intentions": [
    {
      "description": "Voy a empezar a vender empanadas en el barrio para complementar",
      "profile_effects": {
        "employment_type": "self_employed",
        "income_delta": 80000
      },
      "urgency": "high"
    }
  ]
}
```

The LLM generates actions freely — no predefined list. `profile_effects` uses allowed profile fields:
- `employment_type`, `employment_status`
- `income_delta` (relative, clamped +-50% of current income)
- `has_dollars`, `usd_savings_delta`
- `has_debt`
- `housing_type`, `tenure`
- `has_bank_account`, `has_credit_card`

Unrecognized fields are ignored.

### Resolution

In the next introspection, the LLM receives pending intentions and decides their fate. The introspection prompt includes:

```
=== TUS INTENCIONES PENDIENTES ===
- "Voy a empezar a vender empanadas" (urgencia: alta, hace 1 ciclo)
¿Se cumplió, se frustró, o sigue pendiente? Reflexioná sobre esto.
```

The LLM output includes:

```json
{
  "intention_resolutions": [
    {
      "description": "Voy a empezar a vender empanadas",
      "status": "executed",
      "reflection": "Empecé a vender los fines de semana, no es mucho pero ayuda"
    }
  ]
}
```

### IntentionExecutor

- Applies `profile_effects` for executed intentions
- Validates: fields in allowed list, income_delta clamped +-50%
- Marks expired after 2 introspections without resolution
- Max 2 active per actor

## Layer 2: Emergent Bonds

### AffinityTracker (runs after each café)

For each table:
1. For each pair of participants, upsert `actor_bonds`:
   - New pair: `affinity: 0.1, shared_cafes: 1`
   - Existing: `shared_cafes += 1, affinity = min(affinity + 0.15, 1.0)`
   - When `shared_cafes >= 3`: set `formed_at`
2. Update `last_cafe_at`

### Decay (runs at start of each measure)

For all bonds where `last_cafe_at` is older than current measure:
- `affinity -= 0.1`
- If `affinity <= 0`: delete bond

### CafeGrouper modification

Current: group by zone+stratum, split into tables of 5-7.
New: within each zone+stratum group, prefer placing bonded actors together:
1. Build sub-groups around bond clusters
2. Fill remaining seats with unbonded actors from same zone+stratum
3. Not a hard constraint — bonds influence seating but don't override zone+stratum

### In café prompt

Bonded actors are annotated:
```
--- María (ID: uuid) --- [vínculo con Jorge, 5 cafés juntos]
```

Max 10 bonds per actor.

## Layer 3: Cognitive Dissonance

### DissonanceCalculator (runs after MeasureRunner, before EventGenerator)

Computes dissonance per decision:

```
mood_dissonance:
  if agreement and social_anger > 7: (social_anger - 5) / 5
  if agreement and government_trust < 3: (5 - government_trust) / 5
  if not agreement and economic_confidence > 7: (economic_confidence - 5) / 5
  else: 0

history_dissonance:
  if last 3 decisions were opposite to this one: 0.5
  if last 2 were opposite: 0.3
  else: 0

dissonance_index = clamp(mood_dissonance + history_dissonance, 0, 1)
```

Persisted in `decisions.dissonance`.

### Immediate effect: volatility

For next café/measure, the actor's LLM temperature is:
```
temperature = 0.3 + (dissonance * 0.4)
```
Max 0.7. Passed as option to `ClaudeClient.complete`.

### Introspection effect: confrontation

If actor's average dissonance over last 3 measures > 0.4, the introspection prompt includes:

```
=== CONTRADICCIONES DETECTADAS ===
Tu enojo social es alto (8/10) pero aprobaste la última medida.
Tu confianza en el gobierno es baja (2/10) pero apoyaste su política.
Reflexioná sobre estas contradicciones.
```

The LLM resolves by shifting mood or rationalizing beliefs.

### Accumulated dissonance

If dissonance > 0.5 for 3+ consecutive measures without dropping:
- Auto-increment `social_anger` by +0.5
- Unresolved internal tension becomes anger

## Layer 4: Personal Events

### EventGenerator (runs after DissonanceCalculator)

1. **Select actors**: ~20% of population, weighted by vulnerability score:
   ```
   vulnerability = (10 - economic_confidence) / 10
                 + (social_anger / 10)
                 + (if unemployed: 0.3, else: 0)
                 + (if destitute or low: 0.2, else: 0)
                 + (dissonance)
   ```
   Normalize to probability, sample ~200 actors.

2. **Generate event via LLM**: One call per selected actor. Input:
   - Actor profile, current mood, autobiographical narrative
   - The measure that just passed
   - Pending intentions
   - Instruction: "A este ciudadano le pasó algo esta semana. Puede ser consecuencia de la medida o algo de su vida personal. Generá un evento realista."

3. **LLM output**:
   ```json
   {
     "event": "Me echaron del taller. El dueño dijo que con la suba de tarifas no puede mantener tres empleados.",
     "mood_impact": {
       "economic_confidence": -2.0,
       "personal_wellbeing": -1.5,
       "social_anger": 1.0
     },
     "profile_effects": {
       "employment_status": "unemployed",
       "employment_type": "unemployed",
       "income_delta": -350000
     },
     "duration": 4
   }
   ```

4. **Validation**:
   - mood_impact clamped +-2.0 per dimension
   - profile_effects validated against allowed fields
   - income_delta clamped +-70% of current income
   - duration clamped 1-6

### Decay

Each measure: `remaining -= 1` for all active events. When remaining = 0: `active = false`.

Mood impact decays linearly: `current_impact = original_impact * (remaining / duration)`.

### In prompt

```
=== EVENTOS RECIENTES EN TU VIDA ===
- Hace 2 medidas: Me echaron del taller (impacto emocional decayendo)
- Esta semana: Mi hijo empezó la secundaria
```

Max 3 active events per actor.

## Layer 5: Theory of Mind

### Group mood (computed, no LLM)

After each café, for each participant:

```elixir
%{
  group_mood: dominant_mood_label(table_actors),    # "enojados", "esperanzados", etc.
  agreement_ratio: approved_count / total_count,     # 0.0-1.0
  dominant_emotion: dimension_with_largest_avg_delta  # "social_anger", "economic_confidence", etc.
}
```

### Referents (from café LLM output)

The café prompt already generates conversation + effects. Add to the expected output:

```json
{
  "conversation": [...],
  "effects": [...],
  "referents": [
    {
      "actor_id": "uuid",
      "perceived_by": "uuid",
      "influence": "María me hizo ver que la estabilidad del dólar sí nos ayuda",
      "influence_type": "positive"
    }
  ]
}
```

Max 2 referents per actor per café. The LLM determines who influenced whom based on the conversation it generated.

### In prompt

```
=== LO QUE PERCIBÍS DE TU ENTORNO ===
En tu última conversación con vecinos, la mayoría estaba frustrada (70% rechazó la medida).
María te hizo ver que la estabilidad del dólar sí nos ayuda aunque no lo sintamos.
```

### In introspection

Accumulated perceptions are included so the actor reflects on social influence:
- "Noto que mis vecinos me influyen mucho"
- "Pienso distinto a todos los de mi barrio"

## New Modules

| Module | Responsibility |
|--------|----------------|
| `DissonanceCalculator` | Compute dissonance index per decision, auto-anger for accumulated |
| `EventGenerator` | Select vulnerable actors, generate personalized events via LLM |
| `EventDecayer` | Reduce remaining duration, deactivate expired events |
| `AffinityTracker` | Update bond affinity/shared_cafes after each café, decay inactive |
| `TheoryOfMindBuilder` | Compute group mood, persist referents from café output |
| `IntentionExecutor` | Apply profile_effects from resolved intentions, expire old ones |

## Modified Modules

| Module | Change |
|--------|--------|
| `CafeGrouper` | Prioritize bonded actors in table assignment |
| `CafePromptBuilder` | Add bond annotations, request referents in output |
| `CafeResponseValidator` | Validate referents in response |
| `CafeRunner` | Call AffinityTracker + TheoryOfMindBuilder post-café |
| `IntrospectionPromptBuilder` | Add intentions, dissonances, perceptions to prompt |
| `IntrospectionRunner` | Handle intention resolutions, call IntentionExecutor |
| `MeasureRunner` | Pass per-actor temperature (dissonance), inject events + perceptions in prompt |
| `PromptBuilder` | Extend build/5 with events + perceptions blocks |
| `ConsciousnessLoader` | Load events, perceptions, bonds, intentions, dissonance |

## Mix Tasks

```bash
# Existing (modified with new data)
mix sim.run --title "..." --description "..." --population "..." --cafe

# New queries
mix sim.events --population "1000 personas"              # active events summary
mix sim.events --actor-id <id>                            # actor event history
mix sim.bonds --population "1000 personas"                # bond network stats
mix sim.bonds --actor-id <id>                             # actor's bonds
mix sim.dissonance --population "1000 personas"           # dissonance distribution
```

## Validation Targets

- Events are coherent with actor profile and measure context
- Dissonance index correctly identifies contradictory behavior
- Bonds form between actors who repeatedly share cafés
- Intentions resolve meaningfully (not all executed, not all frustrated)
- Referents reflect actual conversation influence
- Temperature increase produces visibly different (more varied) responses
- Profile effects from intentions/events produce realistic actor evolution
