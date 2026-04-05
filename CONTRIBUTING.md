# Contribuir al Simulador de Población

Gracias por tu interés en contribuir. Este proyecto busca crecer y toda contribución es bienvenida — desde reportar bugs hasta proponer nuevas capas de conciencia para los actores.

## Cómo contribuir

### Reportar problemas

Abrí un [issue](../../issues) describiendo:
- Qué esperabas que pasara
- Qué pasó en realidad
- Pasos para reproducir el problema
- Tu versión de Elixir/OTP (`elixir --version`)

### Proponer ideas

¿Tenés una idea para mejorar el simulador? Abrí un issue con el tag **idea** y contanos:
- Qué querés agregar o cambiar
- Por qué creés que mejora la simulación
- Si tenés referencias (papers, datos, etc.)

Algunas áreas donde la ayuda es especialmente valiosa:

- **Sociología computacional** — Mejorar los modelos de comportamiento, calibrar contra datos reales
- **Datos INDEC** — Integrar nuevas fuentes (ENGHO, censo, etc.)
- **Economía** — Validar que las reacciones simuladas tienen sentido macroeconómico
- **NLP/LLM** — Mejorar prompts, grounding, reducir alucinaciones
- **Visualización** — Mejorar la UI, agregar gráficos, dashboards
- **Performance** — Optimizar queries, concurrencia, caching

### Enviar código

1. **Fork** el repositorio
2. Creá una rama desde `main`:
   - `feature/<descripcion>` para funcionalidad nueva
   - `fix/<descripcion>` para bugs
   - `refactor/<descripcion>` para refactoring
3. Escribí tu código siguiendo las convenciones del proyecto (ver abajo)
4. Asegurate de que `mix test` pase
5. Abrí un **Pull Request** describiendo:
   - Qué cambiaste y por qué
   - Si es un feature nuevo, cómo se usa
   - Si modifica datos o calibración, con qué fuente lo validaste

### Convenciones de código

- **Elixir 1.19+**, seguir los patterns existentes del proyecto
- **Tests**: Todo feature nuevo necesita tests. Usamos ExUnit
- **SQL**: Las queries van como `Repo.query!` con parámetros, no inline
- **Prompts**: En español rioplatense (los actores son argentinos del GBA)
- **Commits**: Mensajes claros que expliquen el qué y el por qué

### Calibración y datos

Si tu contribución cambia la estratificación, los umbrales de pobreza, o cualquier dato calibrado:

- Documentá la fuente (INDEC, BCRA, RIPTE, etc.)
- Incluí el período de los datos
- Corré la validación: tu distribución de estratos debe acercarse a los targets INDEC vigentes
- Actualizá el skill de calibración si cambiás los valores (`~/.claude/skills/indec-calibration/`)

### Conciencia de los actores

El sistema de conciencia tiene 8 capas. Si querés agregar una nueva o modificar una existente:

1. Escribí un spec en `docs/superpowers/specs/`
2. Discutí el diseño en un issue antes de implementar
3. Cada capa debe tener:
   - Un módulo claro con responsabilidad única
   - Constraints de grounding (para que el LLM no alucine)
   - Integración con el `PromptBuilder` y el `ConsciousnessLoader`
   - Documentación en `CLAUDE.md`

### LLM y costos

El simulador hace muchas llamadas a la API de Claude. Tené en cuenta:

- Un ciclo completo de 3 medidas cuesta ~5050 llamadas LLM
- Si tu feature agrega llamadas, documentá cuántas y por qué
- Preferí cálculos locales sobre llamadas LLM cuando sea posible
- Temperature 0.3 por defecto para consistencia

## Setup de desarrollo

```bash
# Clonar
git clone https://github.com/waabox/population_simulator.git
cd population_simulator

# Instalar dependencias
mix deps.get

# Base de datos
mix ecto.create
mix ecto.migrate

# Descargar datos EPH
./scripts/download_eph.sh 3 2025

# Generar templates de creencias (necesita API key)
export CLAUDE_API_KEY=sk-ant-...
mix sim.beliefs.init

# Seedear actores
mix sim.seed --n 1000 --population "1000 personas"

# Tests
mix test

# UI
mix phx.server
# Abrir http://localhost:4000
```

## Estructura del proyecto

Consultá el [README](README.md) para la estructura completa de archivos y módulos.

## Licencia

Al contribuir, aceptás que tu código se distribuya bajo la [Apache License 2.0](LICENSE).

## Contacto

- **Autor**: Emiliano Arango
- **Issues**: [GitHub Issues](../../issues)
- **PRs**: Siempre bienvenidos
