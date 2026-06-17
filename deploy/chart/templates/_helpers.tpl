{{/* Base name of the app. */}}
{{- define "demo-app.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Fully qualified name, suffixed by environment so dev/staging/prod can
     coexist if they ever land in the same namespace. */}}
{{- define "demo-app.fullname" -}}
{{- printf "%s-%s" (include "demo-app.name" .) .Values.env | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Common labels applied to every object. */}}
{{- define "demo-app.labels" -}}
app.kubernetes.io/name: {{ include "demo-app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
environment: {{ .Values.env }}
{{- end -}}

{{/* Selector labels — stable subset used by Deployments and Services. */}}
{{- define "demo-app.selectorLabels" -}}
app.kubernetes.io/name: {{ include "demo-app.name" . }}
environment: {{ .Values.env }}
{{- end -}}
