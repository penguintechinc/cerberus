{{/*
Expand the name of the chart.
*/}}
{{- define "cerberus.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "cerberus.fullname" -}}
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
{{- define "cerberus.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "cerberus.labels" -}}
helm.sh/chart: {{ include "cerberus.chart" . }}
{{ include "cerberus.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "cerberus.selectorLabels" -}}
app.kubernetes.io/name: {{ include "cerberus.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "cerberus.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "cerberus.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Return the image registry
*/}}
{{- define "cerberus.image.registry" -}}
{{- default "docker.io" .Values.global.imageRegistry }}
{{- end }}

{{/*
Return the image repository
*/}}
{{- define "cerberus.image.repository" -}}
{{- $registry := include "cerberus.image.registry" . }}
{{- if .repository }}
{{- printf "%s/%s" $registry .repository }}
{{- else }}
{{- printf "%s/%s" $registry "library/.placeholder" }}
{{- end }}
{{- end }}

{{/*
Return the proper image reference
*/}}
{{- define "cerberus.image" -}}
{{- $registry := include "cerberus.image.registry" . }}
{{- if .repository }}
{{- printf "%s/%s:%s" $registry .repository (.tag | default "latest") }}
{{- else }}
{{- printf "%s" (.tag | default "latest") }}
{{- end }}
{{- end }}

{{/*
Return image pull secrets
*/}}
{{- define "cerberus.imagePullSecrets" -}}
{{- with .Values.global.imagePullSecrets }}
imagePullSecrets:
{{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}

{{/*
PostgreSQL connection string
*/}}
{{- define "cerberus.postgresql.dsn" -}}
{{- if .Values.postgresql.enabled }}
postgresql://{{ .Values.postgresql.auth.username }}:{{ .Values.postgresql.auth.password }}@{{ include "cerberus.fullname" . }}-postgresql:5432/{{ .Values.postgresql.auth.database }}
{{- else }}
{{ .Values.externalPostgresql.dsn | default "" }}
{{- end }}
{{- end }}

{{/*
Redis connection string
*/}}
{{- define "cerberus.redis.host" -}}
{{- if .Values.redis.enabled }}
{{ include "cerberus.fullname" . }}-redis-master
{{- else }}
{{ .Values.externalRedis.host | default "localhost" }}
{{- end }}
{{- end }}

{{/*
Redis port
*/}}
{{- define "cerberus.redis.port" -}}
{{- if .Values.redis.enabled }}
6379
{{- else }}
{{ .Values.externalRedis.port | default "6379" }}
{{- end }}
{{- end }}

{{/*
Return pod security context
*/}}
{{- define "cerberus.podSecurityContext" -}}
{{- with .Values.podSecurityContext }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Return security context
*/}}
{{- define "cerberus.securityContext" -}}
{{- with .Values.securityContext }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Return component selector labels
*/}}
{{- define "cerberus.component.selectorLabels" -}}
app.kubernetes.io/name: {{ include "cerberus.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
component: {{ .component }}
{{- end }}

{{/*
Return component labels
*/}}
{{- define "cerberus.component.labels" -}}
{{ include "cerberus.labels" . }}
component: {{ .component }}
{{- end }}

{{/*
Comma-joined list of image pull secrets
*/}}
{{- define "cerberus.imagePullSecretsList" -}}
{{- range .Values.global.imagePullSecrets }}
{{ .name }},
{{- end }}
{{- end }}
