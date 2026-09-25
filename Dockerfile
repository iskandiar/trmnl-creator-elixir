FROM hexpm/elixir:1.18.4-erlang-27.3.4-debian-bookworm-20250428 AS build
RUN apt-get update && apt-get install -y --no-install-recommends build-essential git curl ca-certificates && rm -rf /var/lib/apt/lists/*
WORKDIR /app
ENV MIX_ENV=prod ERL_FLAGS="+JMsingle true"
RUN mix local.hex --force && mix local.rebar --force
COPY mix.exs mix.lock ./
COPY config config
RUN mix deps.get --only prod && mix deps.compile
COPY lib lib
COPY priv priv
RUN mix compile && mix release

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends libstdc++6 openssl libncurses6 locales ca-certificates curl && rm -rf /var/lib/apt/lists/* && useradd -m app
WORKDIR /app
COPY --from=build --chown=app:app /app/_build/prod/rel/trmnl ./
USER app
ENV PHX_SERVER=true LANG=C.UTF-8 ERL_FLAGS="+JMsingle true"
EXPOSE 4000
CMD ["sh", "-c", "bin/trmnl eval 'Trmnl.Release.migrate()' && bin/trmnl start"]
