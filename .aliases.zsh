alias bn="git rev-parse --abbrev-ref HEAD"
alias pb="git rev-parse --abbrev-ref @{-1}"
# brew list aha || brew install aha
alias grd="git range-diff"
function grdf_print() {
    diff=$(grd $1...$2)
    echo "<details>
    <summary>ForcePushRangeDiff</summary>

\`\`\`diff

$diff

\`\`\`

</details>

" >| tmp.txt
    sed -i '' '/^\ -:/d' tmp.txt
    sed -i '' 's/ //' tmp.txt
    sed -i '' 's/ //' tmp.txt
    sed -i '' 's/ //' tmp.txt
    sed -i '' 's/ //' tmp.txt
    cat tmp.txt | pbcopy
    rm tmp.txt
    echo "Git Range-diff copied to clipboard!!"
}
function grdf() {
    bn=$(git rev-parse --abbrev-ref HEAD)
    diff=$(git range-diff origin/$bn...$bn)
    echo "

<details><summary>ForcePushRangeDiff</summary>

\`\`\`diff

$diff

\`\`\`

</details>
" >| tmp.txt
    sed -i '' 's/ //' tmp.txt
    sed -i '' 's/ //' tmp.txt
    sed -i '' 's/ //' tmp.txt
    sed -i '' 's/ //' tmp.txt
    sed -i '' '/^\ -:/d' tmp.txt
    cat tmp.txt | pbcopy
    rm tmp.txt
    echo "Git Range-diff copied to clipboard!!"
}

function set_aliases() {
    # global
    alias kapow='puma-dev -stop && echo -e "\033[32mRestarted puma-dev.\033[0m"'
    alias puma-stop='launchctl unload ~/Library/LaunchAgents/io.puma.dev.plist'
    alias puma-start='launchctl load ~/Library/LaunchAgents/io.puma.dev.plist'
    alias ppuma='ps -ax | grep puma'
    alias mc='cd ~/mycase/mycase_app'
    alias mclogin='cd ~/mycase/mycase_login && git pull && deps && bin/rails db:migrate && kapow && foreman start'
    alias mcnotifs='cd ~/mycase/mycase_notifications && git pull && kapow && foreman start'
    alias pls="bin/yarn"
    # from project directory
    alias deps='nvm use && bin/yarn && bundle'
    alias build='deps && bin/rails db:migrate && kapow'
    alias rt='bundle exec ruby -Itest'
    alias brt='CHROME_DEBUG=1 bundle exec ruby -Itest'
    alias jt='pls test'
    alias debug='bundle exec pry-remote'
    alias dev_logs='tail -f log/development.log'
    alias bullet_logs='tail -f log/bullet.log'
    alias gl="git log --graph --decorate --pretty=oneline --abbrev-commit"
    alias gcu="git reset HEAD^"
    # alias grid="git checkout develop && git pull && git checkout @{-1} && git rebase -i develop"
    alias gs="git status"
    alias be="bundle exec"
    alias migrate="bin/rails db:migrate RAILS_ENV=development"
    alias endpoint="bundle exec rake routes | grep"
    # My fuckin own bitch
    alias kill_puma="pkill -9 puma-dev"
    alias reinstall_puma="puma-dev -uninstall; puma-dev -install"
    alias gr="git rebase --autosquash"
    alias gri="gr -i"
    alias grias="gri --autostash"
    # alias gria="git rebase -i --autosquash"
    alias griod="gri origin/develop"
    # alias griad="gria origin/develop"
    alias gpl="git pull"
    alias gp="git push"
    alias gpf="grdf; gp --force-with-lease"
    alias gro="gri --onto"
    alias gron="gr --onto"
    alias grc="git rebase --continue"
    alias gra="git rebase --abort"
    alias gc="git commit"
    alias gca="gc --amend"
    alias gcan="gca --no-edit"
    alias gcm="gc -m"
    alias gcf="gc --fixup"
    alias ga="git add"
    alias gap="ga -p"
    alias gat="ga test"
    alias gaa="ga app"
    alias gaat="ga app test"
    alias gaac="gaa; gc"
    alias gaacm="gaa; gcm"
    alias gaacf="gaa; gcf"
    alias gaaca="gaa; gca"
    alias gaacarc="gaa; gca; grc"
    alias gaacapf="gaa; gca; gpf"
    alias gaacarcpf="gaa; gca; grc; gpf"
    alias gaacan="gaa; gcan"
    alias gaacanrc="gaa; gcan; grc"
    alias gaacanpf="gaa; gcan; gpf"
    alias gaacanrcpf="gaa; gcan; grc; gpf"
    alias gatc="gat; gc"
    alias gatcm="gat; gcm"
    alias gatcf="gat; gcf"
    alias gatca="gat; gca"
    alias gatcarc="gat; gca; grc"
    alias gatcapf="gat; gca; gpf"
    alias gatcan="gat; gcan"
    alias gatcanrc="gat; gcan; grc"
    alias gatcanpf="gat; gcan; gpf"
    alias gatcanrcpf="gat; gcan; grc; gpf"
    alias gaatc="gaat; gc"
    alias gaatcm="gaat; gcm"
    alias gaatcf="gaat; gcf"
    alias gaatca="gaat; gca"
    alias gaatcarc="gaat; gca; grc"
    alias gaatcapf="gaat; gca; gpf"
    alias gaatcan="gaat; gcan"
    alias gaatcanrc="gaat; gcan; grc"
    alias gaatcanpf="gaat; gcan; gpf"
    alias gaatcanrcpf="gaat; gcan; grc; gpf"
    alias gcp="git cherry-pick"
    alias gch="git checkout"
    alias gchb="git checkout -b"
    alias gchd"gch develop"
    alias gpf="grdf; gp --force-with-lease"
    alias gpfo="gpf origin"
    alias gst="git stash"
    alias gstp="git stash pop"
    alias gf="git fetch"
    alias grid="gf && griod"
    # alias grad="gf && griad"
    alias gbi="git bisect"
    alias gbig="gbi good"
    alias gbib="gbi bad"
    alias grss="git reset --soft"
    alias grssh="git reset --soft HEAD~"
    # alias grsh="git reset --hard"
    alias gres="git restore"
    alias gresc="git restore config"
    alias gress="git restore --staged"
    alias gd="git diff"
    # alias gcl="git clean -df"
    alias gbhis="git reflog | egrep -io \"moving from ([^[:space:]]+)\" | awk '{ print $3 }' | awk ' !x[$0]++' | egrep -v '^[a-f0-9]{40}$' | head -n10"
    # Non-git
    alias fs="foreman start"
    alias puma_logs="tail -n 100 -f ~/Library/Logs/puma-dev.log"
    # alias grdf="git range-diff"
    # Elasticsearch
    alias ski="docker container start kibana"
    alias stki="docker container stop kibana"
    alias startes="docker container start elasticsearch"
    alias stopes="docker container stop elasticsearch"
    alias startes2="docker container start elasticsearch2"
    alias stopes2="docker container stop elasticsearch2"
    alias ses="startes; startes2; ski"
    alias stes="stopes; stopes2; stki"
    # Migration specific
    alias ms="./bin/rails db:migrate:status"
    # Yarn usage
    alias yarnst="yarn start"
    alias ys="yarn start"
    alias ya="yarn add"
    alias yi="yarn install"
    alias yb="yarn build"
    alias yd="yarn deploy"
    alias yt="yarn test"
    alias ye="yarn eject"
    # github pages
    alias ds="gp; yd"
    # for updating aliases specifically
    alias sal="source ~/.aliases.zsh"
    alias updatedf="source ~/.dotfiles/update.sh && sal"
    alias updatedfedit="source ~/.dotfiles/update.sh 1 && sal"
    # alias udf="vim ~/.aliases.zsh; updatedfedit"
    # alias udfn="vim ~/.aliases.zsh; updatedf" # no edit
}
set_aliases

function udf() {
    if [[ "$@" == "" ]]; then
        vim ~/.aliases.zsh
    else
        vim "$@"
    fi
    updatedfedit
}
function udfn() { # no edit
    if [[ "$@" == "" ]]; then
        vim ~/.aliases.zsh
    else
        vim "$@"
    fi
    updatedf
}
function run_in_rc_file() {
    export DISABLE_SPRING=true
}
function run_on_startup() {
    startes
    start_agent
}

function copy() {
    # copies a file to your clipboard
    cat $1 | pbcopy
}
function gpu() {
    git push origin $(bn) -u
}
function grop() {
    gro $(pb) $1
}
function fixup() {
    # first add all the files you wanna commit
    # then call like so -> "fixup <sha of commit>"
    if [ "$1" != "" ] # or better, if [ -n "$1" ]
    then
        gcf "$1"
        grias "$1"^
    fi
}
function gafixup() {
    ga $1
    if [ "$2" != "" ]
    then
        gcf "$2"
        grias "$2"^
    fi
}
# function gchro() {
    # bn=$(git rev-parse --abbrev-ref HEAD)
    # git checkout $1; gro $bn origin/$bn;
    # gch $bn; gpf; gch $1
# }
function kafka() {
    dir="/Users/leonid.belyi/mycase/kafka"
    echo "Running Zookeeper in background (waiting 4 seconds to allow it to start)"
    $dir/bin/zookeeper-server-start.sh $dir/config/zookeeper.properties &
    zookeeperpid=$!
    sleep 4
    $dir/bin/kafka-server-start.sh $dir/config/kafka.dev.server.properties
    # Kill zookeeper once kafka stops
    kill $zookeeperpid
}
function kafkapr() {
    dir="/Users/leonid.belyi/mycase/kafka"
    echo "Type messages to send to topic: \"$1\""
    $dir/bin/kafka-console-producer.sh --broker-list localhost:29092 --topic $1
}
function kibana() {
    dir="/Users/leonid.belyi/mycase/kibana"
    echo "Running Kibana"
    $dir/bin/kibana
}
function setup_es() {
    docker network create esnetwork
    docker run -d --name elasticsearch --net esnetwork -p 9201:9200 -p 9300:9300 -e "discovery.type=single-node" elasticsearch:7.7.0
    docker run -d --name kibana --net esnetwork -p 5601:5601 -e "discovery.type=single-node" -e ELASTICSEARCH_URL=http:elasticsearch:9201 kibana:7.7.0
    docker run -d --name elasticsearch2 --net esnetwork -p 9202:9200 -e "discovery.type=single-node" elasticsearch:7.7.0
}
function mup() {
    ./bin/rails db:migrate:up VERSION=$1
}
function mdown() {
    ./bin/rails db:migrate:down VERSION=$1
}
function gac() {
    ga $1; gc;
}
function gacm() {
    ga $1; gc -m "$2";
}
function gacf() {
    ga $1; gcf $2;
}
function gaca() {
    ga $1; gca;
}
function gacarc() {
    ga $1; gca; grc;
}
function gacapf() {
    ga $1; gca; gpf;
}
function gacan() {
    ga $1; gcan;
}
function gacanrc() {
    ga $1; gcan; grc;
}
function gacanpf() {
    ga $1; gcan; gpf;
}
