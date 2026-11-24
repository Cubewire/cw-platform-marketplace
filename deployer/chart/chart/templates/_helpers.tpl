{{/*
Common labels for all resources
*/}}
{{- define "cubewire.labels" -}}
app.kubernetes.io/name: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: cubewire-platform
{{- end -}}

{{/*
Consumption tracking label — replace LABEL_VALUE with the value from
Producer Portal > Overview > Consumption tracking label
*/}}
{{- define "cubewire.trackingLabel" -}}
goog-packaged-solution: cubewire-platform
{{- end -}}

{{/*
Pod labels: common labels + consumption tracking
*/}}
{{- define "cubewire.podLabels" -}}
{{ include "cubewire.labels" . }}
{{ include "cubewire.trackingLabel" . }}
{{- end -}}

{{/*
Cloud SQL proxy sidecar container
*/}}
{{- define "cubewire.cloudSqlProxy" -}}
- name: cloud-sql-proxy
  image: {{ .Values.cloudSql.proxyImage }}
  args:
    - "--structured-logs"
    - "--port=5432"
    - "--private-ip"
    - "--auto-iam-authn"
    - {{ .Values.cloudSql.connectionName | quote }}
  securityContext:
    runAsNonRoot: true
  resources:
    requests:
      memory: "64Mi"
      cpu: "25m"
    limits:
      memory: "128Mi"
      cpu: "50m"
{{- end -}}
