FROM python:latest

# Setup
VOLUME /tmp
WORKDIR /usr/app/src
ENV SCRIPT_PATH /usr/local/bin/
# Setup python buffer to 1 to dislay logs inside the container
ENV PYTHONUNBUFFERED=1 

# Needed dependencies
COPY requirements.txt /tmp/requirements.txt
RUN pip --cache-dir /tmp/pip install -r /tmp/requirements.txt

# Copy scripts
COPY benchmarking ${SCRIPT_PATH}
