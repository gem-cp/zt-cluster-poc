provider "kubernetes" {
  config_path = "/home/cp/.kube/config"
}

resource "null_resource" "microk8s" {
  provisioner "local-exec" {
    command = <<EOT
    microk8s start
    microk8s status --wait-ready
    microk8s enable dns storage ingress
    mkdir -p ~/.kube
    microk8s kubectl config view --raw > ~/.kube/config
    EOT
  }
}

resource "null_resource" "apply_initial_resources" {
  depends_on = [null_resource.microk8s]

  provisioner "local-exec" {
    command = <<EOT
    microk8s kubectl create namespace argocd
    microk8s kubectl apply -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
    EOT
  }
}

resource "null_resource" "apply_zt_cluster_service" {
  depends_on = [null_resource.apply_initial_resources]

  provisioner "local-exec" {
    command = <<EOT
    microk8s kubectl apply -f https://raw.githubusercontent.com/gem-cp/zt-cluster-poc/main/zt-cluster/zt-cluster-service.yaml
    EOT
  }
}

resource "kubernetes_deployment" "argocd" {
  depends_on = [null_resource.apply_initial_resources]

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
          port {
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
  depends_on = [kubernetes_deployment.argocd]

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

resource "kubernetes_secret" "argocd_admin_password" {
  depends_on = [kubernetes_service.argocd]

  metadata {
    name      = "argocd-secret"
    namespace = "argocd"
  }

  data = {
    "admin.password" = base64encode("admin")
    "admin.passwordMtime" = base64encode("2022-05-12T20:21:12Z")
  }
}

resource "null_resource" "argocd_application" {
  depends_on = [kubernetes_secret.argocd_admin_password]

  provisioner "local-exec" {
    command = <<EOT
    cat <<EOF | microk8s kubectl apply -f -
    apiVersion: argoproj.io/v1alpha1
    kind: Application
    metadata:
      name: zt-cluster
      namespace: argocd
    spec:
      project: default
      source:
        repoURL: "https://github.com/gem-cp/zt-cluster-poc"
        path: "zt-cluster"
        targetRevision: "main"
      destination:
        server: "https://kubernetes.default.svc"
        namespace: "default"
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
    EOF
    EOT
  }
}
