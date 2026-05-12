# ==============================================================
# .zshrc - interactive zsh configuration
# ==============================================================

# --- Homebrew (must come before oh-my-zsh so plugins like autojump find the binary) ---
eval "$(/opt/homebrew/bin/brew shellenv)"

# --- oh-my-zsh ---
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="cobalt2"  # custom theme at ~/.oh-my-zsh/custom/themes/cobalt2.zsh-theme
plugins=(autojump zsh-syntax-highlighting)
source $ZSH/oh-my-zsh.sh

# --- additional PATH ---
export PATH="/opt/homebrew/opt/mysql-client@8.0/bin:$PATH"
export PATH="$HOME/.rbenv/bin:$PATH"
export PATH="$HOME/.local/bin:$PATH"

# --- version managers ---
which rbenv > /dev/null && eval "$(rbenv init -)"
unset RBENV_VERSION

eval "$(pyenv init --path)"
eval "$(pyenv init - --no-rehash)"
alias pip="pip3"

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# --- gcloud SDK ---
if [ -f "$HOME/mycase/google-cloud-sdk/path.zsh.inc" ]; then
    . "$HOME/mycase/google-cloud-sdk/path.zsh.inc"
fi
if [ -f "$HOME/mycase/google-cloud-sdk/completion.zsh.inc" ]; then
    . "$HOME/mycase/google-cloud-sdk/completion.zsh.inc"
fi

# --- general env ---
export CLICOLOR=1
export ENV=DEVELOPMENT
export DISABLE_SPRING=true
export OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES
export DOCKER_BUILDKIT=1
export COMPOSE_DOCKER_CLI_BUILD=1
export MYSQL_PORT=3307
export MYSQL_TCP_PORT=3307
unset BITBUCKET_HTTPS

# --- MyCase user-specific env (review/update on new machine) ---
export AWS_USERNAME="leonidbelyi"
export S3_UPLOAD_BUCKET="dev.mycase.us-east-1.document-search"
export SQS_REQUEST_QUEUE_NAME="dev_leonidbelyi_document_parse_request"
export SQS_COMPLETE_QUEUE_NAME="dev_leonidbelyi_document_parsed"

# --- ssh-agent: reuse existing or start a new one ---
# Keys are stored in the macOS Keychain (`ssh-add --apple-use-keychain`),
# so the passphrase prompt only happens once — the first time a key is
# loaded after it's added to ~/.ssh. Every shell after that (interactive,
# Claude Code, VSCode terminal, etc.) gets the key automatically because
# launchd's default agent reads from Keychain too.
SSH_ENV="$HOME/.ssh/agent-environment"
function start_agent() {
    echo "Initialising new SSH agent..."
    /usr/bin/ssh-agent | sed 's/^echo/#echo/' > "$SSH_ENV"
    chmod 600 "$SSH_ENV"
    . "$SSH_ENV" > /dev/null
    # `--apple-use-keychain` stores the passphrase in Keychain on first
    # add, and loads from Keychain on subsequent adds. With keys listed
    # explicitly here, additional ones can just be appended to the line.
    /usr/bin/ssh-add --apple-use-keychain "$HOME/.ssh/id_ed25519"
}
if [ -f "$SSH_ENV" ]; then
    . "$SSH_ENV" > /dev/null
    if ! { [ -n "$SSH_AGENT_PID" ] && ps -p "$SSH_AGENT_PID" > /dev/null 2>&1; }; then
        start_agent
    fi
else
    start_agent
fi

# --- aliases & functions ---
[ -f "$HOME/.aliases.zsh" ] && source "$HOME/.aliases.zsh"
