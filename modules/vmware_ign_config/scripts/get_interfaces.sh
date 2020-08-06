#!/bin/bash

PRIVATE_IP=$1
PRIVATE_INT=$(ip a | grep -B2 "${PRIVATE_IP}" | awk '$1!="inet" && $1!="link/ether" {print $2}'| cut -d':' -f1)
echo {\"privateintf\": \"${PRIVATE_INT}\"}