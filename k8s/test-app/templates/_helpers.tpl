{{- define "test-app.fullname" -}}
{{ .Release.Name }}
{{- end }}

{{- define "test-app.labels" -}}
app: {{ include "test-app.fullname" . }}
chart: {{ .Chart.Name }}-{{ .Chart.Version }}
release: {{ .Release.Name }}
{{- end }}

{{- define "test-app.selectorLabels" -}}
app: {{ include "test-app.fullname" . }}
{{- end }}