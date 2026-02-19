{{/*
Expand the name of the chart.
*/}}
{{- define "formae.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "formae.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "formae.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "formae.labels" -}}
helm.sh/chart: {{ include "formae.chart" . }}
{{ include "formae.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "formae.selectorLabels" -}}
app.kubernetes.io/name: {{ include "formae.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "formae.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "formae.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
formae container image
*/}}
{{- define "formae.image" -}}
{{- $tag := default .Chart.AppVersion .Values.image.tag -}}
{{- printf "%s:%s" .Values.image.repository $tag -}}
{{- end }}

{{/*
PostgreSQL host — either in-cluster or external
*/}}
{{- define "formae.postgres.host" -}}
{{- if .Values.postgresql.enabled }}
{{- printf "%s-postgresql" (include "formae.fullname" .) }}
{{- else }}
{{- .Values.formae.datastore.postgres.host }}
{{- end }}
{{- end }}

{{/*
PostgreSQL password secret name
*/}}
{{- define "formae.postgres.secretName" -}}
{{- if .Values.postgresql.enabled }}
  {{- if .Values.postgresql.auth.existingSecret }}
    {{- .Values.postgresql.auth.existingSecret }}
  {{- else }}
    {{- printf "%s-postgresql" (include "formae.fullname" .) }}
  {{- end }}
{{- else if .Values.formae.datastore.postgres.existingSecret }}
  {{- .Values.formae.datastore.postgres.existingSecret }}
{{- else }}
  {{- printf "%s-db" (include "formae.fullname" .) }}
{{- end }}
{{- end }}

{{/*
PostgreSQL password secret key
*/}}
{{- define "formae.postgres.secretKey" -}}
{{- if .Values.postgresql.enabled }}
  {{- default "password" .Values.postgresql.auth.existingSecretKey }}
{{- else }}
  {{- default "password" .Values.formae.datastore.postgres.existingSecretKey }}
{{- end }}
{{- end }}

{{/*
Grafana dashboard namespace
*/}}
{{- define "formae.grafana.namespace" -}}
{{- default .Release.Namespace .Values.grafana.dashboards.namespace }}
{{- end }}
