{{/*
Expand the name of the chart.
*/}}
{{- define "xboard.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this
(by the DNS naming spec). If release name contains chart name it will be used as
a full name.
*/}}
{{- define "xboard.fullname" -}}
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
{{- define "xboard.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Render a per-component resource name in the form "<fullname>-<role>".
Truncated to 63 chars to comply with DNS naming spec.

Usage:
  {{ include "xboard.componentName" (dict "ctx" $ "role" "web") }}
*/}}
{{- define "xboard.componentName" -}}
{{- $fullname := include "xboard.fullname" .ctx }}
{{- printf "%s-%s" $fullname .role | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels applied to every rendered resource.
Merges optional .Values.commonLabels at the end.
*/}}
{{- define "xboard.labels" -}}
helm.sh/chart: {{ include "xboard.chart" . }}
app.kubernetes.io/name: {{ include "xboard.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: xboard
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Component labels = common labels + app.kubernetes.io/component.
Intentionally omits the legacy "app: <role>" label.

Usage:
  {{ include "xboard.componentLabels" (dict "ctx" $ "role" "web") }}
*/}}
{{- define "xboard.componentLabels" -}}
{{ include "xboard.labels" .ctx }}
app.kubernetes.io/component: {{ .role }}
{{- end }}

{{/*
Selector labels — the three immutable identifiers used in
Deployment/StatefulSet selectors and matching Service selectors.
Must remain stable across upgrades.

Usage:
  {{ include "xboard.selectorLabels" (dict "ctx" $ "role" "web") }}
*/}}
{{- define "xboard.selectorLabels" -}}
app.kubernetes.io/name: {{ include "xboard.name" .ctx }}
app.kubernetes.io/instance: {{ .ctx.Release.Name }}
app.kubernetes.io/component: {{ .role }}
{{- end }}

{{/*
Resolve a per-component container image reference.
Falls back from role-specific overrides to the top-level image.* values,
and ultimately to Chart.AppVersion for the tag.

Usage:
  {{ include "xboard.image" (dict "ctx" $ "role" "web") }}
*/}}
{{- define "xboard.image" -}}
{{- $roleValues := index .ctx.Values .role | default dict -}}
{{- $roleImage := get $roleValues "image" | default dict -}}
{{- $repo := $roleImage.repository | default .ctx.Values.image.repository -}}
{{- $tag := $roleImage.tag | default .ctx.Values.image.tag | default .ctx.Chart.AppVersion -}}
{{- printf "%s:%s" $repo $tag -}}
{{- end }}

{{/*
Resolve the imagePullPolicy for a component.
Order of precedence:
  1. Role-specific .image.pullPolicy
  2. Top-level .Values.image.pullPolicy
  3. Smart default based on tag — Always for "" or "latest", IfNotPresent otherwise.

Usage:
  {{ include "xboard.imagePullPolicy" (dict "ctx" $ "role" "web") }}
*/}}
{{- define "xboard.imagePullPolicy" -}}
{{- $roleValues := index .ctx.Values .role | default dict -}}
{{- $roleImage := get $roleValues "image" | default dict -}}
{{- $override := $roleImage.pullPolicy | default .ctx.Values.image.pullPolicy -}}
{{- if $override -}}
{{- $override -}}
{{- else -}}
{{- $tag := $roleImage.tag | default .ctx.Values.image.tag -}}
{{- if or (eq $tag "") (eq $tag "latest") -}}
Always
{{- else -}}
IfNotPresent
{{- end -}}
{{- end -}}
{{- end }}

{{/*
Name of the Secret holding the application config (.env values).
Honors .Values.config.existingSecret when provided.
*/}}
{{- define "xboard.configSecretName" -}}
{{- if .Values.config.existingSecret -}}
{{- .Values.config.existingSecret -}}
{{- else -}}
{{- printf "%s-config" (include "xboard.fullname" .) -}}
{{- end -}}
{{- end }}

{{/*
Resolve the Laravel APP_KEY rendered into the config Secret.

Precedence:
  1. .Values.config.values.APP_KEY when non-empty — caller-provided value wins.
  2. Existing in-cluster Secret with the same name — preserves the key across
     re-renders so pods are not invalidated on every `helm upgrade`.
  3. Freshly generated `base64:<32-char-base64>` value.

Stability caveat: when neither (1) nor (2) applies (e.g. `helm template`
without --is-upgrade, dry-run installs, or a brand-new namespace) a new key
is generated on each render. For reproducibility either set
config.values.APP_KEY explicitly or reference an existingSecret.
*/}}
{{- define "xboard.appKey" -}}
{{- $provided := index .Values.config.values "APP_KEY" -}}
{{- if $provided -}}
{{- $provided -}}
{{- else -}}
{{- $secretName := include "xboard.configSecretName" . -}}
{{- $existing := lookup "v1" "Secret" .Release.Namespace $secretName -}}
{{- if and $existing $existing.data (hasKey $existing.data "APP_KEY") -}}
{{- index $existing.data "APP_KEY" | b64dec -}}
{{- else -}}
{{- printf "base64:%s" (randAlphaNum 32 | b64enc) -}}
{{- end -}}
{{- end -}}
{{- end }}

{{/*
Render env entries that explicitly disable a set of feature flags for a
component. Each flag is uppercased and prefixed with ENABLE_, set to "false".

Usage:
  {{ include "xboard.disabledFlagsEnv" (dict "ctx" $ "flags" (list "caddy" "horizon" "ws_server" "redis")) }}
*/}}
{{- define "xboard.disabledFlagsEnv" -}}
{{- range .flags }}
- name: ENABLE_{{ . | upper }}
  value: "false"
{{- end }}
{{- end }}

{{/*
Checksum of the rendered application config.
Used as a pod annotation to trigger rolling restarts when config changes.
When an external secret is referenced, falls back to a hash of its name.
*/}}
{{- define "xboard.configChecksum" -}}
{{- if .Values.config.existingSecret -}}
{{- .Values.config.existingSecret | sha256sum -}}
{{- else -}}
{{- toJson .Values.config.values | sha256sum -}}
{{- end -}}
{{- end }}
