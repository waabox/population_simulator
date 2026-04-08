FROM hexpm/elixir:1.19.5-erlang-26.2.5.2-debian-bookworm-20260316

RUN apt-get update && apt-get install -y git build-essential cmake && rm -rf /var/lib/apt/lists/*

WORKDIR /app

ENV MIX_ENV=dev

RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock ./
RUN mix deps.get

COPY config/ config/
COPY assets/ assets/
COPY lib/ lib/
COPY priv/ priv/
COPY scripts/ scripts/
COPY population_simulator_dev.db ./

RUN mix deps.compile && mix assets.build && mix compile

EXPOSE 4000

ENV PHX_IP=0.0.0.0

CMD ["mix", "phx.server"]
