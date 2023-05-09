#!/bin/bash 

source ./format_display.sh

log 'G-H' "Preparing host for running Auto Benchmarking of MySQL using sysbench.."

# install git
sudo yum install git -y

# install nvm and npm
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.3/install.sh | bash
. ~/.nvm/nvm.sh
nvm install --lts

# install cdk
npm install -g aws-cdk

# set venv and bootstrap cdk
python3 -m venv .venv
source .venv/bin/activate
python3 -m pip install --upgrade pip
pip install -r requirements.txt    
cdk bootstrap

log 'G-H' "PREP WORK COMPLETE!!"