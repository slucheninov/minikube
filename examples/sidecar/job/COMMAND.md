# Команды для запуска
# Примените манифест
kubectl apply -f job-with-sidecar.yaml

# Наблюдайте за статусом Job
kubectl get jobs -w

# В другом терминале - логи основного контейнера
POD_NAME=$(kubectl get pods --selector=job-name=data-processor-job -o jsonpath='{.items[0].metadata.name}')
kubectl logs -f $POD_NAME -c data-processor

# В третьем терминале - логи sidecar (мониторинг прогресса)
kubectl logs -f $POD_NAME -c progress-monitor

# После завершения проверьте статус (должно быть COMPLETIONS: 1/1)
kubectl get jobs

# Проверьте Pod (должен быть в статусе Completed)
kubectl get pods --selector=job-name=data-processor-job

# Убедитесь, что все контейнеры завершились
kubectl get pods $POD_NAME -o jsonpath='{.status.containerStatuses[*].state}' | jq

# Очистка
kubectl delete -f job-with-sidecar.yaml