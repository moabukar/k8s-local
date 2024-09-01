#!/bin/bash
# Fails on errors
set -o errexit

kind delete cluster
