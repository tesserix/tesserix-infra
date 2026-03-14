# =============================================================================
# K8S BOOTSTRAP — Install cluster addons via Helm
# =============================================================================
# Order: Istio base → Istiod → Knative → cert-manager → ESO → ArgoCD → Kargo
# After this stack runs, ArgoCD takes over GitOps for all app workloads.
# =============================================================================

# ---------------------------------------------------------------------------
# Namespaces (created before Helm releases)
# ---------------------------------------------------------------------------
resource "kubectl_manifest" "namespaces" {
  for_each = toset([
    "platform", "shared", "marketplace", "ingress", "monitoring",
    "knative-serving", "external-secrets", "kargo",
  ])

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Namespace"
    metadata = {
      name = each.key
      labels = merge(
        { "app.kubernetes.io/part-of" = "tesserix" },
        contains(["platform", "shared", "marketplace"], each.key) ? { "istio-injection" = "enabled" } : {}
      )
    }
  })
}

# ---------------------------------------------------------------------------
# 1. Istio (base + istiod)
# ---------------------------------------------------------------------------
resource "helm_release" "istio_base" {
  name             = "istio-base"
  repository       = "https://istio-release.storage.googleapis.com/charts"
  chart            = "base"
  version          = "1.24.2"
  namespace        = "istio-system"
  create_namespace = true

  set {
    name  = "defaultRevision"
    value = "default"
  }
}

resource "helm_release" "istiod" {
  name       = "istiod"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "istiod"
  version    = "1.24.2"
  namespace  = "istio-system"

  depends_on = [helm_release.istio_base]

  values = [yamlencode({
    pilot = {
      env = {
        PILOT_ENABLE_WORKLOAD_ENTRY_AUTOREGISTRATION = "true"
      }
      resources = {
        requests = { cpu = "100m", memory = "256Mi" }
        limits   = { memory = "512Mi" }
      }
    }
    meshConfig = {
      accessLogFile = "/dev/stdout"
      enableTracing = true
      defaultConfig = {
        holdApplicationUntilProxyStarts = true
      }
    }
    global = {
      proxy = {
        autoInject = "enabled"
        resources = {
          requests = { cpu = "10m", memory = "40Mi" }
          limits   = { memory = "256Mi" }
        }
      }
    }
    cni = {
      enabled = false # CNI not compatible with GKE Autopilot
    }
  })]
}

# Istio CNI removed — not compatible with GKE Autopilot (requires NET_ADMIN,
# SYS_ADMIN capabilities and hostPath write mounts which Autopilot blocks).
# Sidecar injection works without CNI on Autopilot.

resource "helm_release" "istio_ingress" {
  name       = "istio-ingressgateway"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "gateway"
  version    = "1.24.2"
  namespace  = "istio-system"

  depends_on = [helm_release.istiod]

  values = [yamlencode({
    service = {
      type = "ClusterIP" # No public LB — Cloudflare Tunnel handles ingress
    }
    autoscaling = {
      minReplicas = 2
      maxReplicas = 5
    }
    resources = {
      requests = { cpu = "100m", memory = "128Mi" }
      limits   = { memory = "256Mi" }
    }
  })]
}

# ---------------------------------------------------------------------------
# 2. Knative Serving
# ---------------------------------------------------------------------------
resource "helm_release" "knative_operator" {
  name             = "knative-operator"
  repository       = "https://knative.github.io/operator"
  chart            = "knative-operator"
  version          = "1.17.1"
  namespace        = "knative-serving"
  create_namespace = false

  depends_on = [kubectl_manifest.namespaces]
}

resource "kubectl_manifest" "knative_serving" {
  yaml_body = yamlencode({
    apiVersion = "operator.knative.dev/v1beta1"
    kind       = "KnativeServing"
    metadata = {
      name      = "knative-serving"
      namespace = "knative-serving"
    }
    spec = {
      version = "1.17"
      ingress = {
        istio = { enabled = true }
      }
      config = {
        network = {
          "ingress-class" = "istio.ingress.networking.knative.dev"
        }
        autoscaler = {
          "enable-scale-to-zero"              = "true"
          "scale-to-zero-grace-period"        = "30s"
          "scale-to-zero-pod-retention-period" = "0s"
          "stable-window"                     = "60s"
          "max-scale-up-rate"                 = "1000.0"
        }
        defaults = {
          "revision-timeout"     = "300s"
          "max-revision-timeout" = "600s"
        }
        deployment = {
          "progress-deadline"                      = "600s"
          "queue-sidecar-cpu-request"               = "25m"
          "queue-sidecar-cpu-limit"                  = "200m"
          "queue-sidecar-memory-request"             = "50Mi"
          "queue-sidecar-memory-limit"               = "200Mi"
          "queue-sidecar-ephemeral-storage-request"  = "50Mi"
          "queue-sidecar-ephemeral-storage-limit"    = "200Mi"
        }
      }
    }
  })

  depends_on = [helm_release.knative_operator, helm_release.istiod]
}

# ---------------------------------------------------------------------------
# 3. cert-manager (Kargo dependency + TLS)
# ---------------------------------------------------------------------------
resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = "1.17.1"
  namespace        = "cert-manager"
  create_namespace = true
  timeout          = 600

  set {
    name  = "crds.enabled"
    value = "true"
  }

  # GKE Autopilot blocks kube-system access — use cert-manager namespace for leader election
  set {
    name  = "global.leaderElection.namespace"
    value = "cert-manager"
  }

  # Disable startup API check — it times out on Autopilot while nodes provision
  set {
    name  = "startupapicheck.enabled"
    value = "false"
  }

  values = [yamlencode({
    resources = {
      requests = { cpu = "25m", memory = "64Mi" }
      limits   = { memory = "256Mi" }
    }
    cainjector = {
      resources = {
        requests = { cpu = "10m", memory = "32Mi" }
        limits   = { memory = "128Mi" }
      }
    }
    webhook = {
      resources = {
        requests = { cpu = "10m", memory = "32Mi" }
        limits   = { memory = "128Mi" }
      }
    }
  })]
}

# ---------------------------------------------------------------------------
# 4. External Secrets Operator
# ---------------------------------------------------------------------------
resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = "0.14.1"
  namespace        = "external-secrets"
  create_namespace = false

  depends_on = [kubectl_manifest.namespaces]

  values = [yamlencode({
    serviceAccount = {
      annotations = {
        "iam.gke.io/gcp-service-account" = "sa-eso-controller@${var.project_id}.iam.gserviceaccount.com"
      }
    }
    resources = {
      requests = { cpu = "25m", memory = "64Mi" }
      limits   = { memory = "256Mi" }
    }
    webhook = {
      resources = {
        requests = { cpu = "25m", memory = "64Mi" }
        limits   = { memory = "256Mi" }
      }
    }
    certController = {
      resources = {
        requests = { cpu = "10m", memory = "32Mi" }
        limits   = { memory = "128Mi" }
      }
    }
  })]
}

# ClusterSecretStore — single store for all namespaces
resource "kubectl_manifest" "cluster_secret_store" {
  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ClusterSecretStore"
    metadata = {
      name = "gcp-secret-manager"
    }
    spec = {
      provider = {
        gcpsm = {
          projectID = var.project_id
          auth = {
            workloadIdentity = {
              clusterLocation = var.region
              clusterName     = data.terraform_remote_state.gke.outputs.cluster_name
              serviceAccountRef = {
                name      = "external-secrets"
                namespace = "external-secrets"
              }
            }
          }
        }
      }
    }
  })

  depends_on = [helm_release.external_secrets]
}

# ---------------------------------------------------------------------------
# 5. ArgoCD
# ---------------------------------------------------------------------------
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "7.8.3"
  namespace        = "argocd"
  create_namespace = true

  values = [yamlencode({
    server = {
      service = { type = "ClusterIP" }
      resources = {
        requests = { cpu = "25m", memory = "64Mi" }
        limits   = { memory = "256Mi" }
      }
    }
    configs = {
      params = {
        "server.insecure" = true # TLS terminated at Cloudflare
      }
      cm = {
        "application.resourceTrackingMethod" = "annotation"
        "resource.exclusions" = yamlencode([{
          apiGroups = ["cilium.io"]
          kinds     = ["CiliumIdentity"]
          clusters  = ["*"]
        }])
      }
    }
    controller = {
      resources = {
        requests = { cpu = "50m", memory = "256Mi" }
        limits   = { memory = "512Mi" }
      }
    }
    repoServer = {
      resources = {
        requests = { cpu = "25m", memory = "64Mi" }
        limits   = { memory = "256Mi" }
      }
    }
    dex = {
      resources = {
        requests = { cpu = "10m", memory = "32Mi" }
        limits   = { memory = "128Mi" }
      }
    }
    redis = {
      resources = {
        requests = { cpu = "10m", memory = "16Mi" }
        limits   = { memory = "128Mi" }
      }
    }
    notifications = {
      resources = {
        requests = { cpu = "10m", memory = "32Mi" }
        limits   = { memory = "128Mi" }
      }
    }
    applicationSet = {
      resources = {
        requests = { cpu = "10m", memory = "64Mi" }
        limits   = { memory = "256Mi" }
      }
    }
  })]
}

# ---------------------------------------------------------------------------
# 6. Kargo
# ---------------------------------------------------------------------------
resource "helm_release" "kargo" {
  name             = "kargo"
  repository       = "oci://ghcr.io/akuity/kargo-charts"
  chart            = "kargo"
  version          = "1.3.1"
  namespace        = "kargo"
  create_namespace = false

  depends_on = [kubectl_manifest.namespaces, helm_release.cert_manager]

  values = [yamlencode({
    api = {
      service = { type = "ClusterIP" }
      adminAccount = {
        passwordHash    = var.kargo_admin_password_hash
        tokenSigningKey = var.kargo_token_signing_key
      }
      resources = {
        requests = { cpu = "25m", memory = "64Mi" }
        limits   = { memory = "256Mi" }
      }
    }
    controller = {
      argocd = {
        integrationEnabled = true
        namespace          = "argocd"
      }
      argoRollouts = {
        integrationEnabled = false
      }
      resources = {
        requests = { cpu = "25m", memory = "64Mi" }
        limits   = { memory = "256Mi" }
      }
    }
    managementController = {
      resources = {
        requests = { cpu = "10m", memory = "32Mi" }
        limits   = { memory = "128Mi" }
      }
    }
    webhooksServer = {
      resources = {
        requests = { cpu = "10m", memory = "32Mi" }
        limits   = { memory = "128Mi" }
      }
    }
    garbageCollector = {
      resources = {
        requests = { cpu = "10m", memory = "32Mi" }
        limits   = { memory = "128Mi" }
      }
    }
  })]
}
