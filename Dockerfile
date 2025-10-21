ARG NODE_VERSION=22.16.0

FROM node:$NODE_VERSION AS builder

# Install Foundry
RUN curl -L https://foundry.paradigm.xyz | bash
RUN /root/.foundry/bin/foundryup -i stable \
    && rm /root/.foundry/bin/foundryup \
    && strip /root/.foundry/bin/*

WORKDIR /app
COPY package.json yarn.lock .yarnrc.yml foundry.toml soldeer.lock ./
RUN corepack enable && corepack install
RUN PATH="$PATH:/root/.foundry/bin" yarn install --immutable
RUN PATH="$PATH:/root/.foundry/bin" forge soldeer install

COPY ./ ./

RUN PATH="$PATH:/root/.foundry/bin" yarn build

# Removed files we don't want to copy to destination container
RUN rm -rf .yarn

FROM node:$NODE_VERSION-slim AS deploy

RUN apt-get update \
    && apt-get upgrade -y \
    && apt-get install -y --no-install-recommends \
      gettext-base \
      jq \
      patch \
    && apt clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
WORKDIR /app
COPY --from=builder /root/.foundry/bin/ /usr/local/bin/
COPY --from=builder /root/.svm/ /root/.svm/
COPY --from=builder /app/ /app/
RUN corepack enable && corepack install

# Only to validate that forge is working properly
RUN forge build --offline

ENTRYPOINT [ "/usr/local/bin/yarn" ]
CMD [ "deploy:tenderly" ]
