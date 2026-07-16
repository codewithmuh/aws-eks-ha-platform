{{/*
Workload archetypes. A consuming chart picks one by including the matching
template. All of them inherit the security defaults from _helpers.tpl.

  platform-lib.deployment     web / scalable-worker / fenced-singleton
  platform-lib.service        ClusterIP fronting the pods
  platform-lib.pdb            keep >= N pods during voluntary disruption
  platform-lib.hpa            scale a stateless worker on load
  platform-lib.migrationJob   schema migration, ordered before the app (sync-wave -1)
*/}}

{{- define "platform-lib.deployment" -}}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "platform-lib.fullname" . }}
  labels:
    {{- include "platform-lib.labels" . | nindent 4 }}
spec:
  replicas: {{ .Values.replicaCount | default 2 }}
  {{- with .Values.strategy }}
  strategy:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  selector:
    matchLabels:
      {{- include "platform-lib.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "platform-lib.selectorLabels" . | nindent 8 }}
      {{- with .Values.podAnnotations }}
      annotations:
        {{- toYaml . | nindent 8 }}
      {{- end }}
    spec:
      {{- with .Values.serviceAccountName }}
      serviceAccountName: {{ . }}
      {{- end }}
      securityContext:
        {{- include "platform-lib.podSecurityContext" . | nindent 8 }}
      {{- if .Values.spreadAcrossZones | default true }}
      # Spread replicas across AZs and nodes so losing one zone can't take the service down.
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: ScheduleAnyway
          labelSelector:
            matchLabels:
              {{- include "platform-lib.selectorLabels" . | nindent 14 }}
        - maxSkew: 1
          topologyKey: kubernetes.io/hostname
          whenUnsatisfiable: ScheduleAnyway
          labelSelector:
            matchLabels:
              {{- include "platform-lib.selectorLabels" . | nindent 14 }}
      {{- end }}
      containers:
        {{- include "platform-lib.container" . | nindent 8 }}
{{- end -}}


{{- define "platform-lib.service" -}}
apiVersion: v1
kind: Service
metadata:
  name: {{ include "platform-lib.fullname" . }}
  labels:
    {{- include "platform-lib.labels" . | nindent 4 }}
spec:
  type: {{ .Values.service.type | default "ClusterIP" }}
  selector:
    {{- include "platform-lib.selectorLabels" . | nindent 4 }}
  ports:
    - name: http
      port: {{ .Values.service.port | default 8000 }}
      targetPort: http
{{- end -}}


{{- define "platform-lib.pdb" -}}
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: {{ include "platform-lib.fullname" . }}
  labels:
    {{- include "platform-lib.labels" . | nindent 4 }}
spec:
  minAvailable: {{ .Values.pdb.minAvailable | default 1 }}
  selector:
    matchLabels:
      {{- include "platform-lib.selectorLabels" . | nindent 6 }}
{{- end -}}


{{- define "platform-lib.hpa" -}}
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: {{ include "platform-lib.fullname" . }}
  labels:
    {{- include "platform-lib.labels" . | nindent 4 }}
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: {{ include "platform-lib.fullname" . }}
  minReplicas: {{ .Values.hpa.minReplicas | default 2 }}
  maxReplicas: {{ .Values.hpa.maxReplicas | default 6 }}
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: {{ .Values.hpa.targetCPU | default 70 }}
{{- end -}}


{{- define "platform-lib.migrationJob" -}}
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ include "platform-lib.fullname" . }}-migrate
  labels:
    {{- include "platform-lib.labels" . | nindent 4 }}
  annotations:
    # Helm runs this before the app; Argo CD orders it one wave earlier.
    "helm.sh/hook": pre-install,pre-upgrade
    "helm.sh/hook-weight": "-5"
    "helm.sh/hook-delete-policy": before-hook-creation,hook-succeeded
    argocd.argoproj.io/sync-wave: "-1"
spec:
  backoffLimit: {{ .Values.migration.backoffLimit | default 3 }}
  template:
    metadata:
      labels:
        {{- include "platform-lib.selectorLabels" . | nindent 8 }}
    spec:
      restartPolicy: Never
      securityContext:
        {{- include "platform-lib.podSecurityContext" . | nindent 8 }}
      containers:
        - name: migrate
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
          imagePullPolicy: {{ .Values.image.pullPolicy | default "IfNotPresent" }}
          command:
            {{- toYaml .Values.migration.command | nindent 12 }}
          {{- with .Values.env }}
          env:
            {{- range $k, $v := . }}
            - name: {{ $k }}
              value: {{ $v | quote }}
            {{- end }}
          {{- end }}
          securityContext:
            {{- include "platform-lib.containerSecurityContext" . | nindent 12 }}
{{- end -}}
