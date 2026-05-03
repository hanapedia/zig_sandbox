#!/usr/bin/env bash

while true; do
  kubectl scale deployment watch-debug --replicas=0
  sleep 20
  kubectl scale deployment watch-debug --replicas=1
  sleep 20
done
