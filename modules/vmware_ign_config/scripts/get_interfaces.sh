#!/bin/bash

PRIVATE_IP=$1

PRIVATE_INT=$(sudo ifconfig | grep -B1 "${PRIVATE_IP}" | awk '$1!="inet" && $1!="--" {print $1}'| cut -d':' -f1)
echo {\"privateintf\": \"${PRIVATE_INT}\"}