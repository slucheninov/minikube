# Команды для запуска
# Примените манифест (ConfigMap и Pod)
kubectl apply -f envoy-proxy-sidecar.yaml

# Подождите готовности
kubectl wait --for=condition=Ready pod/envoy-proxy-demo --timeout=60s

# Проверьте логи клиентского приложения
kubectl logs envoy-proxy-demo -c client-app --tail=20

# Проверьте access логи Envoy
kubectl logs envoy-proxy-demo -c envoy-proxy --tail=30

# Сделайте запрос через прокси вручную
kubectl exec envoy-proxy-demo -c client-app -- curl -s localhost:8080/headers

# Откройте admin интерфейс Envoy
kubectl port-forward envoy-proxy-demo 9901:9901 &

# В браузере откройте http://localhost:9901
# Или через curl
curl http://localhost:9901/stats

# Проверьте статистику кластеров
curl http://localhost:9901/clusters

# Остановите port-forward
pkill -f "port-forward envoy-proxy-demo"

# Очистка
kubectl delete -f envoy-proxy-sidecar.yaml
