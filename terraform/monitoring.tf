# -----------------------------------------------------------------------------
# Monitoring Stack: kube-prometheus-stack + Jaeger
# -----------------------------------------------------------------------------

resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
  }

  depends_on = [aws_eks_node_group.main]
}

resource "helm_release" "kube_prometheus_stack" {
  name       = "kube-prometheus-stack"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = "82.3.0"

  values = [
    templatefile("${path.module}/helm-values/kube-prometheus-stack.yaml", {
      grafana_admin_password = var.grafana_admin_password
    })
  ]

  depends_on = [
    kubernetes_namespace.monitoring,
    aws_eks_node_group.main,
  ]
}

resource "helm_release" "jaeger" {
  name       = "jaeger"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  repository = "https://jaegertracing.github.io/helm-charts"
  chart      = "jaeger"
  version    = "4.5.0"

  values = [
    file("${path.module}/helm-values/jaeger.yaml")
  ]

  depends_on = [
    kubernetes_namespace.monitoring,
    aws_eks_node_group.main,
  ]
}

resource "kubernetes_config_map" "grafana_dashboard" {
  metadata {
    name      = "grafana-dashboard-microservices"
    namespace = kubernetes_namespace.monitoring.metadata[0].name

    labels = {
      grafana_dashboard = "1"
    }
  }

  data = {
    "microservices.json" = file("${path.module}/../k8s/observability/grafana/dashboards/microservices.json")
  }

  depends_on = [helm_release.kube_prometheus_stack]
}
