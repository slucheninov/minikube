# Команды для запуска
# Примените манифест
kubectl apply -f git-sync-sidecar.yaml

# Подождите, пока git-sync загрузит репозиторий
kubectl wait --for=condition=Ready pod/git-sync-web --timeout=180s

# Проверьте логи git-sync
kubectl logs git-sync-web -c git-sync

# Проверьте синхронизированные файлы
kubectl exec git-sync-web -c nginx -- ls -la /usr/share/nginx/html/ | head -20

# Откройте доступ к веб-серверу
kubectl port-forward git-sync-web 8080:80 &

# Откройте в браузере http://localhost:8080
# Или используйте curl
curl http://localhost:8080

# Проверьте, что файлы обновляются (подождите 60 секунд)
kubectl logs git-sync-web -c git-sync --tail=20

# Остановите port-forward
pkill -f "port-forward git-sync-web"

# Очистка
kubectl delete -f git-sync-sidecar.yaml