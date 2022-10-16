# Use python image as source of our custom image
FROM python:latest

# Setup
VOLUME /tmp
WORKDIR /usr/app/src
ENV SCRIPT_PATH /usr/local/bin/
# Setup python buffer to 1 to dislay logs inside the container
ENV PYTHONUNBUFFERED=1 

# Needed dependencies
# Copy the requirement file from the local to the container
COPY requirements.txt /tmp/requirements.txt
# Install python dependencies
RUN pip --cache-dir /tmp/pip install -r /tmp/requirements.txt

# Copy script
COPY benchmarking ${SCRIPT_PATH}
