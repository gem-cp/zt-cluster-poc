#!/bin/bash
microk8s kubectl config view --raw > ~/.kube/config
microk8s enable dns && microk8s stop && microk8s start
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

  

