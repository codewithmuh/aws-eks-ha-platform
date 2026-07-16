{{/* Common naming + labels shared by every archetype. */}}

{{- define "platform-lib.fullname" -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "platform-lib.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: aws-eks-ha-platform
{{- end -}}

{{- define "platform-lib.selectorLabels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Pod-level security context — the "restricted" Pod Security Admission baseline.
Applied to every archetype so no workload can opt out by omission.
*/}}
{{- define "platform-lib.podSecurityContext" -}}
runAsNonRoot: true
runAsUser: 10001
fsGroup: 10001
seccompProfile:
  type: RuntimeDefault
{{- end -}}

{{/* Container-level security context — least privilege. */}}
{{- define "platform-lib.containerSecurityContext" -}}
allowPrivilegeEscalation: false
capabilities:
  drop: ["ALL"]
{{- end -}}

{{/*
The shared container spec — image, port, env (with optional downward-API POD_NAME
for leader election), probes, resources. Consumed by both the Deployment and Job.
*/}}
{{- define "platform-lib.container" -}}
- name: {{ .Chart.Name }}
  image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
  imagePullPolicy: {{ .Values.image.pullPolicy | default "IfNotPresent" }}
  ports:
    - name: http
      containerPort: {{ .Values.service.port | default 8000 }}
  {{- if or .Values.downwardPodName .Values.env }}
  env:
    {{- if .Values.downwardPodName }}
    - name: POD_NAME
      valueFrom:
        fieldRef:
          fieldPath: metadata.name
    {{- end }}
    {{- range $k, $v := .Values.env }}
    - name: {{ $k }}
      value: {{ $v | quote }}
    {{- end }}
  {{- end }}
  {{- with .Values.envFrom }}
  envFrom:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  securityContext:
    {{- include "platform-lib.containerSecurityContext" . | nindent 4 }}
  {{- if .Values.probes.enabled | default true }}
  readinessProbe:
    httpGet:
      path: {{ .Values.probes.readyPath | default "/readyz" }}
      port: http
    initialDelaySeconds: {{ .Values.probes.readyInitialDelay | default 5 }}
    periodSeconds: 5
  livenessProbe:
    httpGet:
      path: {{ .Values.probes.livePath | default "/healthz" }}
      port: http
    initialDelaySeconds: {{ .Values.probes.liveInitialDelay | default 10 }}
    periodSeconds: 10
  {{- end }}
  resources:
    {{- toYaml (.Values.resources | default dict) | nindent 4 }}
{{- end -}}
