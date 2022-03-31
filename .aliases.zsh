alias bn="git rev-parse --abbrev-ref HEAD"
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
    # Migration specific
    alias ms="./bin/rails db:migrate:status"
    alias yarnst="yarn start"
    alias ys="yarn start"
    alias ya="yarn add"
    alias yi="yarn install"
    alias yb="yarn build"
    alias yd="yarn deploy"
    alias yt="yarn test"
    alias ye="yarn eject"
    # for updating aliases specifically
    alias udf="source ~/.dotfiles/update.sh && source ~/.aliases.zsh"
}
set_aliases

function gchb() {
    git checkout -b $1; git push -u origin $1
}
function fixup() {
    # first add all the files you wanna commit
    # then call like so -> "fixup <sha of commit>"
    if [ "$1" != "" ] # or better, if [ -n "$1" ]
    then
        gcf "$1"
        gri --autostash "$1"^
    fi
}
function gafixup() {
    ga $1
    if [ "$2" != "" ]
    then
        gcf "$2"
        gri --autostash "$2"^
    fi
}
# function gchro() {
    # bn=$(git rev-parse --abbrev-ref HEAD)
    # git checkout $1; gro $bn origin/$bn;
    # gch $bn; gpf; gch $1
# }
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
