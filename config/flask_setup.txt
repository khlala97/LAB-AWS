#!/bin/bash

sudo apt-get update
sudo apt-get -y upgrade

sudo apt install python3 python3-pip -y
sudo apt install python3-venv

sudo mkdir flask_application && cd flask_application
sudo python3 -m venv venv
sudo source venv/bin/activate

sudo pip3 install flask 
sudo pip3 install flask-restful
sudo pip3 install ec2_metadata

sudo touch my_app.py
sudo cat > my_app.py  <<EOL
from ec2_metadata import ec2_metadata
from flask import Flask

app = Flask(__name__)

@app.route('/')
def home():
    return "Welcome to cluster benchmarking"

@app.route('/cluster1')
def cluster_1():
    return f"Instance id: {ec2_metadata.instance_id} is responding from cluster 1!"

@app.route('/cluster2')
def cluster_2():
    return f"Instance id: {ec2_metadata.instance_id} is responding from cluster 2!"

EOL

export FLASK_APP=my_app.py
nohup flask run --host=0.0.0.0 --port=80 > log.txt 2>&1 &
