FROM debian:12

# 刻意保留 /var/lib/apt/lists:fixture 與安裝器都要能在離線索引下 apt-get install zsh。
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      git curl ca-certificates sudo procps passwd less

# 預先抓一份 oh-my-zsh 與 plugin 當 seed,給「已經裝好」的 fixture 用,
# 免得每個 fixture 都重新 clone 一次。
RUN mkdir -p /opt/seed \
 && git clone --depth=1 -q https://github.com/ohmyzsh/ohmyzsh.git /opt/seed/oh-my-zsh \
 && mkdir -p /opt/seed/oh-my-zsh/custom/themes /opt/seed/oh-my-zsh/custom/plugins \
 && git clone --depth=1 -q https://github.com/romkatv/powerlevel10k.git \
      /opt/seed/oh-my-zsh/custom/themes/powerlevel10k \
 && git clone --depth=1 -q https://github.com/zsh-users/zsh-autosuggestions.git \
      /opt/seed/oh-my-zsh/custom/plugins/zsh-autosuggestions \
 && git clone --depth=1 -q https://github.com/zdharma-continuum/fast-syntax-highlighting.git \
      /opt/seed/oh-my-zsh/custom/plugins/fast-syntax-highlighting \
 && git clone --depth=1 -q https://github.com/zsh-users/zsh-completions.git \
      /opt/seed/oh-my-zsh/custom/plugins/zsh-completions

RUN useradd -m -s /bin/bash tester \
 && echo 'tester ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/tester

USER tester
WORKDIR /home/tester
