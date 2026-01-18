# Quick Start: OpenResty Deployment с Sidecar

Production-ready Nginx (OpenResty) Deployment с реальными задержками и двумя sidecar контейнерами.

## 🚀 Запуск за 2 минуты

```bash
# 1. Запустить Minikube
minikube start

# 2. Применить манифест
kubectl apply -f nginx-deployment-openresty.yaml

# 3. Дождаться готовности (все Pod'ы должны быть 3/3 READY)
kubectl wait --for=condition=available --timeout=120s deployment/nginx-with-sidecar

# 4. Проверить Pod'ы
kubectl get pods -l app=nginx-app

# 5. Открыть доступ
kubectl port-forward service/nginx-service 8080:80
```

## 📦 Что развернуто?

- ✅ **OpenResty 1.25.3.1** (Nginx + Lua) - 3 реплики
- ✅ **Log Aggregator sidecar** - сбор и агрегация логов
- ✅ **Nginx Exporter sidecar** - метрики для Prometheus
- ✅ **LoadBalancer Service**
- ✅ **HorizontalPodAutoscaler** (3-10 реплик)
- ✅ **Реальные задержки** через Lua (ngx.sleep)

## 🎯 Доступные endpoints

```bash
# Быстрый ответ
curl http://localhost:8080/
# Hello from Nginx Pod: nginx-with-sidecar-xxx
# Time: ...

# Health check
curl http://localhost:8080/health
# healthy

# Медленный endpoint (2 секунды задержки)
time curl http://localhost:8080/slow
# Slow response from: nginx-with-sidecar-xxx
# Delayed for 2 seconds
# real    0m2.025s

# Случайная задержка (1-5 секунд)
time curl http://localhost:8080/random-delay
# Random delay: 3 seconds
# Pod: nginx-with-sidecar-xxx
# real    0m3.018s

# CPU intensive endpoint (для тестирования автоскейлинга)
curl http://localhost:8080/cpu-intensive
# CPU intensive task completed
# Iterations: 10000000
# Pod: nginx-with-sidecar-xxx
```

## 🧪 Тесты с задержками

### Тест 1: Проверка задержки

```bash
# Сделать 5 запросов к /slow и измерить время
for i in {1..5}; do
  echo "Request $i:"
  time curl -s http://localhost:8080/slow
  echo "---"
done

# Каждый запрос должен занимать ~2 секунды
```

### Тест 2: Параллельные запросы к /slow

```bash
# 10 параллельных запросов
seq 1 10 | xargs -P 10 -I {} sh -c 'time curl -s http://localhost:8080/slow > /dev/null'

# Проверить логи - должны видеть все 10 запросов
POD=$(kubectl get pods -l app=nginx-app -o jsonpath='{.items[0].metadata.name}')
kubectl logs $POD -c log-aggregator --tail=20
```

### Тест 3: Случайные задержки

```bash
# 20 запросов с случайной задержкой
for i in {1..20}; do
  echo -n "Request $i: "
  time curl -s http://localhost:8080/random-delay | grep "Random delay"
done

# Задержки должны быть разные (от 1 до 5 секунд)
```

## 🔥 Тестирование автоскейлинга

### Генерация нагрузки с CPU-intensive endpoint

```bash
# Терминал 1: Наблюдение за HPA
watch -n 2 'kubectl get hpa nginx-hpa'

# Терминал 2: Наблюдение за Pod'ами
watch -n 2 'kubectl get pods -l app=nginx-app'

# Терминал 3: Генерация нагрузки
kubectl run load-test --image=curlimages/curl:8.5.0 --rm -it --restart=Never -- sh -c '
  while true; do
    curl -s http://nginx-service/cpu-intensive > /dev/null
    curl -s http://nginx-service/slow > /dev/null
    sleep 0.1
  done
'

# Вы увидите:
# - CPU utilization растет
# - HPA начинает масштабирование
# - Количество реплик увеличивается от 3 до 10
```

### Генерация нагрузки - множественные клиенты

```bash
# Запустить 5 параллельных load-generator'ов
for i in {1..5}; do
  kubectl run load-gen-$i --image=busybox:1.36 --restart=Never -- sh -c '
    while true; do
      wget -q -O- http://nginx-service/cpu-intensive > /dev/null
      sleep 0.5
    done
  ' &
done

# Наблюдать за масштабированием
kubectl get hpa nginx-hpa -w

# Остановить генераторы
kubectl delete pod -l run=load-gen
```

## 📊 Мониторинг логов

### Логи всех Pod'ов одновременно

```bash
# Последние 10 строк от всех Pod'ов
kubectl logs -l app=nginx-app -c log-aggregator --tail=10 --prefix

# Следить в реальном времени
kubectl logs -l app=nginx-app -c log-aggregator -f

# В другом терминале генерировать трафик
while true; do
  curl -s http://localhost:8080/ > /dev/null
  curl -s http://localhost:8080/slow > /dev/null
  sleep 1
done
```

### Логи конкретного контейнера

```bash
POD=$(kubectl get pods -l app=nginx-app -o jsonpath='{.items[0].metadata.name}')

# Логи OpenResty (главный контейнер)
kubectl logs $POD -c nginx

# Логи log-aggregator sidecar
kubectl logs $POD -c log-aggregator --tail=50

# Логи nginx-exporter sidecar
kubectl logs $POD -c nginx-exporter
```

## 📈 Метрики Prometheus

```bash
# Открыть порт метрик
kubectl port-forward service/nginx-service 9113:9113 &

# Получить все метрики
curl http://localhost:9113/metrics

# Фильтровать метрики nginx
curl -s http://localhost:9113/metrics | grep '^nginx_'

# Конкретные метрики
curl -s http://localhost:9113/metrics | grep -E 'nginx_up|nginx_connections'

# Остановить port-forward
pkill -f "port-forward.*9113"
```

## 🔄 Тестирование Rolling Update

```bash
# Обновить версию OpenResty
kubectl set image deployment/nginx-with-sidecar \
  nginx=openresty/openresty:1.25.3.2-alpine

# Следить за процессом (в одном терминале)
kubectl rollout status deployment/nginx-with-sidecar

# Непрерывные запросы (в другом терминале)
while true; do
  curl -s http://localhost:8080/ || echo "FAILED"
  sleep 0.5
done

# Не должно быть ошибок - Zero Downtime!

# Проверить историю
kubectl rollout history deployment/nginx-with-sidecar

# Откатить если нужно
kubectl rollout undo deployment/nginx-with-sidecar
```

## 🎯 Проверка всех sidecar контейнеров

### Log Aggregator Sidecar

```bash
# Сгенерировать трафик
for i in {1..20}; do
  curl -s http://localhost:8080/random-delay > /dev/null &
done
wait

# Проверить логи - должны видеть все запросы с временем ответа
kubectl logs -l app=nginx-app -c log-aggregator --tail=30

# Вывод должен показывать:
# [ACCESS] [nginx-with-sidecar-xxx] IP - - [timestamp] "GET /random-delay" 200 ... rt=2.005
```

### Nginx Exporter Sidecar

```bash
# Сделать несколько запросов
for i in {1..10}; do curl -s http://localhost:8080/ > /dev/null; done

# Проверить метрики
kubectl port-forward service/nginx-service 9113:9113 &
curl -s http://localhost:9113/metrics | grep nginx_http_requests_total

# Счетчик должен увеличиться на 10
```

## 🧹 Проверка работы контейнеров

```bash
POD=$(kubectl get pods -l app=nginx-app -o jsonpath='{.items[0].metadata.name}')

# Список всех контейнеров
kubectl get pod $POD -o jsonpath='{range .spec.containers[*]}{.name}{"\n"}{end}'
# nginx

kubectl get pod $POD -o jsonpath='{range .spec.initContainers[*]}{.name}{"\t"}{.restartPolicy}{"\n"}{end}'
# log-aggregator	Always
# nginx-exporter	Always

# Статус всех контейнеров
kubectl get pod $POD -o jsonpath='{range .status.containerStatuses[*]}{.name}{"\t"}{.ready}{"\t"}{.restartCount}{"\n"}{end}'

# Потребление ресурсов
kubectl top pod $POD --containers
```

## 🐛 Troubleshooting

### OpenResty не запускается

```bash
# Проверить события
kubectl describe pod $POD

# Проверить логи OpenResty
kubectl logs $POD -c nginx

# Проверить конфигурацию
kubectl exec $POD -c nginx -- cat /usr/local/openresty/nginx/conf/nginx.conf
```

### Lua не работает

```bash
# Проверить, что используется OpenResty, а не стандартный Nginx
kubectl get pod $POD -o jsonpath='{.spec.containers[0].image}'
# Должно быть: openresty/openresty:1.25.3.1-alpine

# Тест Lua
kubectl exec $POD -c nginx -- /usr/local/openresty/bin/openresty -v
# openresty/1.25.3.1
```

### Задержки не работают

```bash
# Проверить endpoint /slow
time curl http://localhost:8080/slow

# Если возвращается мгновенно - проверить ConfigMap
kubectl get configmap nginx-config -o yaml | grep -A 10 "location /slow"

# Должна быть строка: ngx.sleep(2)
```

## 📊 Сравнение с стандартным Nginx

| Функция | Nginx Alpine | OpenResty Alpine |
|---------|--------------|------------------|
| Размер образа | ~25MB | ~130MB |
| Lua поддержка | ❌ | ✅ |
| Задержки (sleep) | ❌ | ✅ ngx.sleep() |
| Динамическая логика | ❌ | ✅ Lua scripts |
| Performance | 100% | ~95% (минимальный overhead) |
| Production ready | ✅ | ✅ |

## 💡 Полезные команды

```bash
# Масштабировать вручную
kubectl scale deployment nginx-with-sidecar --replicas=5

# Изменить параметры HPA
kubectl patch hpa nginx-hpa -p '{"spec":{"maxReplicas":15}}'

# Получить URL в Minikube
minikube service nginx-service --url

# Следить за всеми логами
stern nginx-with-sidecar -c log-aggregator
# (требует установки stern: https://github.com/stern/stern)

# Benchmark с Apache Bench
ab -n 1000 -c 10 http://localhost:8080/
ab -n 100 -c 5 http://localhost:8080/slow
```

## 🎓 Примеры использования Lua

### Добавить свой endpoint с Lua

```yaml
# В ConfigMap добавить:
location /custom {
  content_by_lua_block {
    local name = ngx.var.arg_name or "Guest"
    ngx.say("Hello, ", name, "!")
    ngx.say("Current time: ", ngx.time())
  }
}
```

```bash
# Применить изменения
kubectl apply -f nginx-deployment-openresty.yaml

# Перезапустить Pod'ы
kubectl rollout restart deployment/nginx-with-sidecar

# Тест
curl http://localhost:8080/custom?name=Slava
# Hello, Slava!
# Current time: 1736956123
```

## 🔗 Полезные ссылки

- [OpenResty Documentation](https://openresty.org/en/)
- [Lua Nginx Module API](https://github.com/openresty/lua-nginx-module)
- [OpenResty Best Practices](https://openresty.org/en/best-practices.html)

## 🧹 Очистка

```bash
# Удалить все ресурсы
kubectl delete -f nginx-deployment-openresty.yaml

# Проверить
kubectl get all -l app=nginx-app

# Остановить все port-forward
pkill -f "kubectl port-forward"
```

---

**Готово к production использованию!** 🚀

Все endpoints работают, задержки реальные, sidecar'ы собирают логи и метрики.