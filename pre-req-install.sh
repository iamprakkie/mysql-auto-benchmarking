#!/bin/bash 

sudo yum install git -y

# installing nvm and npm
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.3/install.sh | bash
. ~/.nvm/nvm.sh
nvm install --lts

# install cdk
npm install -g aws-cdk