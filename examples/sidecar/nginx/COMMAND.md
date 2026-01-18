# Команды для запуска
# Примените манифест
kubectl apply -f nginx-logging-sidecar.yaml

# Проверьте статус (ждем READY 2/2)
kubectl get pods -w

# Сделайте несколько запросов
kubectl exec nginx-logging-sidecar -c nginx -- curl -s localhost
kubectl exec nginx-logging-sidecar -c nginx -- curl -s localhost
kubectl exec nginx-logging-sidecar -c nginx -- curl -s localhost

# Проверьте логи sidecar - должны увидеть access логи
kubectl logs nginx-logging-sidecar -c log-reader

# Можно следить за логами в реальном времени
kubectl logs -f nginx-logging-sidecar -c log-reader

# В другом терминале генерируйте трафик
while true; do kubectl exec nginx-logging-sidecar -c nginx -- curl -s localhost > /dev/null; sleep 1; done

# Очистка
kubectl delete -f nginx-logging-sidecar.yaml
