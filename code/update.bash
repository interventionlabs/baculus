#!/bin/bash
# baculus update script
set -ex
HOME=/home/pi
LOG=$HOME/log/baculus.log

fix_modules() {
  sudo rmmod 8192cu
  sudo modprobe rtl8192cu
}

install_baculus() {
  grep '^installed baculus$' $LOG && return
  echo 'installing baculus'
  git clone https://github.com/baculus-buoy/baculus.git
  pushd baculus
  sudo apt install -y ruby ruby-dev
  bundle --version || sudo gem install bundler
  bundle install
  bundle exec jekyll build
  pushd _site
  sed -i -e 's/^.*oogle.*$//' *html */*html
  popd # _site
  popd # baculus
  echo 'installed baculus'
}

configure_npm() {
  export NPM_CONFIG_PREFIX=$HOME/npm/global
  mkdir -p $NPM_CONFIG_PREFIX
  echo NPM_CONFIG_PREFIX=$NPM_CONFIG_PREFIX | sudo tee -a /etc/environment
  export PATH=$NPM_CONFIG_PREFIX/bin:$PATH
  echo PATH=$PATH | sudo tee -a /etc/environment
}

install_tileserver() {
  grep '^installed tileserver$' $LOG && return
  echo 'installing tileserver'
  npm install -g tileserver-gl-light
  cp home/pi/tileserver.json $HOME/
  cp -r home/pi/tiles $HOME/
  sudo cp etc/systemd/system/tileserver.service /etc/systemd/system/
  sudo systemctl daemon-reload
  sudo systemctl enable tileserver
  sudo systemctl start tileserver
  echo 'installed tileserver'
}

meshpoint() {
  test -f $HOME/meshpoint.sh || {
  echo 'installing meshpoint.sh'
    cp home/pi/meshpoint.sh $HOME/meshpoint.sh
    echo 'installed meshpoint.sh'
  }
  bash $HOME/meshpoint.sh
}

adhoc() {
  lsmod | grep 8192cu && sudo rmmod 8192cu
  sudo modprobe rtl8192cu
  test -f $HOME/adhoc.sh || {
  echo 'installing adhoc.sh'
    cp home/pi/adhoc.sh $HOME/adhoc.sh
    echo 'installed adhoc.sh'
  }
  bash $HOME/adhoc.sh
}

configure_nginx() {
  grep 'configured nginx' $LOG && return
  echo 'configuring nginx'
  sudo cp etc/nginx/sites-available/baculus /etc/nginx/sites-available/
  sudo ln -s /etc/nginx/sites-available/baculus /etc/nginx/sites-enabled/baculus
  sudo rm /etc/nginx/sites-enabled/default
  sudo systemctl enable nginx
  echo 'configured nginx'
}

configure_hosts() {
  grep "configured hosts" $LOG && return
  echo 'configuring hosts'
  local config=/etc/hosts
  printf "
127.0.0.1 baculus $HOSTNAME
10.0.42.1 baculus.mesh baculus.map baculus.chat
" | sudo tee -a $config
  echo 'configured hosts'
}

configure_dnsmasq() {
  grep '^configured dnsmasq$' $LOG && return
  echo 'configuring dnsmasq'
  sudo cp etc/dnsmasq.conf /etc/
  echo 'configured dnsmasq'
}

update_rclocal() {
  grep '^updated rclocal$' $LOG && return
  echo 'updating rclocal'
  printf \ '
# setup adhoc mode
/home/pi/adhoc.sh
ip addr
' | sudo tee -a /etc/rc.local
  echo 'updated rc.local'
}

install_scuttlebot() {
  grep '^installed scuttlebot$' $LOG && return
  echo 'installing scuttlebot'
  cd $HOME
  # multiserver
  git clone https://github.com/jedahan/multiserver.git --branch routerless
  pushd multiserver
  git checkout 93e96755fc2dfe1cfa37386a92e4e9d87c3378bc
  npm install
  popd # multiserver
  # broadcast-stream
  git clone https://github.com/jedahan/broadcast-stream.git --branch routerless
  pushd broadcast-stream
  git checkout 53e28ee7be3a247a62dc6f7003d2c89b9a38770e
  npm install
  popd # broadcast-stream
  # scuttlebot
  git clone https://github.com/jedahan/scuttlebot.git --branch routerless
  pushd scuttlebot
  git checkout 7ed0c946a833212406ee492f27a29ba239669d6f
  npm install
  npm link ../broadcast-stream
  npm link ../multiserver
  popd # scuttlebot
  # appname
  echo ssb_appname=bac | sudo tee -a /etc/environment
  echo 'installed scuttlebot'
}

install_mvd() {
  grep '^installed mvd$' $LOG && return
  echo 'installing mvd'
  cd $HOME
  git clone https://github.com/jedahan/mvd --branch routerless
  pushd mvd
  git checkout d8a4a9ffc444a9daa612ede79049083a4ce1ca7c
  npm install
  npm link ../scuttlebot
  popd # mvd
  echo 'installed mvd'
}

install_cjdns() {
  grep '^installed cjdns$' $LOG && return
  echo 'installing cjdns'
  cd $HOME
  git clone https://github.com/cjdelisle/cjdns.git
  pushd cjdns
  git pull
  git checkout 77259a49e5bc7ca7bc6dca5bd423e02be563bdc5
  NO_TEST=1 Seccomp_NO=1 ./do
  sudo cp cjdroute /usr/bin/
  cjdroute --genconf | sed -e 's/"bind": "all"/"bind": "eth0"/' | sudo tee /etc/cjdroute.conf
  sudo cp contrib/systemd/cjdns* /etc/systemd/system/
  popd #cjdns
  echo 'installed cjdns'
}

mkdir -p $(dirname $LOG) && touch $LOG || exit 1
echo "--- START" $(date) >> $LOG
cd $HOME || return
install_baculus &>$LOG
configure_npm &>$LOG
install_cjdns &>$LOG
configure_dnsmasq &>$LOG
configure_nginx &>$LOG
install_scuttlebot &>$LOG
install_mvd &>$LOG
install_tileserver &>$LOG
adhoc &>$LOG
update_rclocal &>$LOG
echo "--- END" $(date) >> $LOG
