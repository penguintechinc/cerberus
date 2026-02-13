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
Get the image name for a component
*/}}
{{- define "cerberus.image" -}}
{{- $registry := .context.Values.global.imageRegistry | default .component.image.registry | default "docker.io" -}}
{{- $repository := .component.image.repository -}}
{{- $tag := .component.image.tag | default .context.Chart.AppVersion -}}
{{- if $registry }}
{{- printf "%s/%s:%s" $registry $repository $tag }}
{{- else }}
{{- printf "%s:%s" $repository $tag }}
{{- end }}
{{- end }}

{{/*
Create environment variables from a map
*/}}
{{- define "cerberus.env" -}}
{{- range $key, $value := . }}
- name: {{ $key }}
  value: {{ $value | quote }}
{{- end }}
{{- end }}

{{/*
Component specific labels
*/}}
{{- define "cerberus.componentLabels" -}}
app.kubernetes.io/component: {{ .component }}
{{ include "cerberus.labels" .context }}
{{- end }}

{{/*
Component specific selector labels
*/}}
{{- define "cerberus.componentSelectorLabels" -}}
app.kubernetes.io/component: {{ .component }}
{{ include "cerberus.selectorLabels" .context }}
{{- end }}
