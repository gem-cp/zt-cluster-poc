provider "kubernetes" {
  config_path = "~/.kube/config"
}

resource "null_resource" "microk8s" {
  provisioner "local-exec" {
    command = <<EOT
    microk8s start
    microk8s status --wait-ready
    microk8s enable dns storage ingress
    microk8s kubectl config view --raw > ~/.kube/config
    microk8s kubectl apply -f https://raw.githubusercontent.com/gem-cp/zt-cluster-poc/main/zt-cluster/zt-cluster-service.yaml
    EOT
  }

  provisioner "local-exec" {
    command = <<EOT
    microk8s kubectl create namespace argocd
    microk8s kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
    EOT
  }
}

resource "kubernetes_deployment" "argocd" {
  metadata {
    name      = "argocd-server"
    namespace = "argocd"
    labels = {
      app = "argocd-server"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "argocd-server"
      }
    }

    template {
      metadata {
        labels = {
          app = "argocd-server"
        }
      }

      spec {
        container {
          name  = "argocd-server"
          image = "argoproj/argocd:v2.3.3"
          ports {
            container_port = 8080
          }

          env {
            name  = "ARGOCD_OPTS"
            value = "--insecure"
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "argocd" {
  metadata {
    name      = "argocd-server"
    namespace = "argocd"
  }

  spec {
    selector = {
      app = "argocd-server"
    }

    port {
      port        = 80
      target_port = 8080
    }
  }
}

resource "kubernetes_secret" "argocd_repo" {
  metadata {
    name      = "argocd-repo-secret"
    namespace = "argocd"
    labels = {
      "argocd.argoproj.io/secret-type" = "repository"
    }
  }

  data = {
    url      = "https://github.com/gem-cp/zt-cluster-poc"
    password = base64encode("<GITHUB_TOKEN>")
    username = base64encode("your-github-username")
  }
}

resource "kubernetes_secret" "argocd_admin_password" {
  metadata {
    name      = "argocd-secret"
    namespace = "argocd"
  }

  data = {
    "admin.password" = base64encode("admin")
    "admin.passwordMtime" = base64encode("2022-05-12T20:21:12Z")
  }
}

resource "kubernetes_application" "zt_cluster" {
  metadata {
    name      = "zt-cluster"
    namespace = "argocd"
  }

  spec {
    project = "default"
    source {
      repoURL = "https://github.com/gem-cp/zt-cluster-poc"
      path    = "zt-cluster"
      targetRevision = "main"
    }

    destination {
      server = "https://kubernetes.default.svc"
      namespace = "default"
    }

    syncPolicy {
      automated {
        prune = true
        selfHeal = true
      }
    }
  }
}
