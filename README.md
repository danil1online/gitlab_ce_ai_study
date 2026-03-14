## Назначение
Учебный gitlab сервер на 120 студентов -- "поток" из 4 групп с числом студентов -- до 30 в каждой. 
## Особенности:
* В свои репозитории студенты загружают отчеты о выполненных практических работах в виде *.ipynb. Сервис должен их проверять с использованием LLM, выдавать заключение.
* Требования к аппаратному обеспечению -- пониженные. Тестирование выполнялось на ПК с
  * Ubuntu 22.04
  * 16 Gb RAM
  * Intel(R) Core(TM) i3-2100 CPU @ 3.10GHz
  * GTX 1060 3Gb / Driver Version: 570.211.01
* Предполагаются шифры групп: pia, ista, istb, pa, наименование учетных записей: student_{группа}_{порядковый номер}

## Порядок настройки
## LLM Server
Используем проект llama.cpp. 
Плюсы:
* В процессе компиляции возможна наиболее точная подстройка под особенности аппаратного обеспечения, что обеспечивает максимальную скорость инференса
* Возможность запуска моделей с функционалом vision без GUI интерфейса

Минус:
* Постоянно занимает VRAM под модель + контест
  
### Установка llama.cpp
```bash
cd ~
sudo apt update
sudo apt install build-essential git cmake ccache
wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb
sudo dpkg -i cuda-keyring_1.1-1_all.deb
sudo apt-get update
sudo apt-get -y install cuda-toolkit-11-8 # Стабильнее всего работает с GTX | Pascal
git clone https://github.com/ggml-org/llama.cpp.git
cd llama.cpp
# Включаем возможность использования видеокарты Nvidia Pascal
cmake -B build\
 -DGGML_CUDA=ON\
 -DGGML_CUDA_F16=ON\
 -DCMAKE_CUDA_ARCHITECTURES=61\
 -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=ON
cmake --build build --config Release -j$(nproc)
```

### Выбор модели
Анализ по состоянию на март 2026 г. показал, что с русским языком качественно работают модели Qwen3.5. Кроме того, они имеют возможность обработки графиков из ipynb.

Учитывая 
* особенности аппаратной конфигурации,
* возможный объем отчета (т.е. нужен запас в VRAM под контекст)

выбрана модель из [Qwen3.5-0.8B-GGUF](https://huggingface.co/unsloth/Qwen3.5-0.8B-GGUF)

Для обработки
* текста -- Qwen3.5-0.8B-Q4_K_M.gguf;
* изображений -- mmproj-F16.gguf (сохранена, как mmproj-F16_0_8.gguf)

Модели размещены в том же каталоге ~/llama.cpp

### Проверка запуска сервера модели:
```bash
/home/user/llama.cpp/build/bin/llama-server\
 -m /home/user/llama.cpp/Qwen3.5-0.8B-Q4_K_M.gguf\
 --mmproj /home/user/llama.cpp/mmproj-F16_0_8.gguf\
 -ngl 99 -c 32768 --host 0.0.0.0 --port 8080
```
здесь:
* /home/user/llama.cpp/build/bin/llama-server -- путь к основному исполняемому файлу
* /home/user/llama.cpp/Qwen3.5-0.8B-Q4_K_M.gguf -- путь к текстовой части модели
* /home/user/llama.cpp/mmproj-F16_0_8.gguf -- путь к visual части модели
* -ngl 99 -- выгрузка модели полностью на GPU
* -c 32768 -- размер контекста
* --host 0.0.0.0 -- запуск сервере для всей локальной сети
* --port 8080 -- порт для доступа

После запуска:
```bash
watch nvidia-smi
```
показывает, что llama.cpp-server занял 2160MiB из 3072MiB доступных; остается место под доп. контекст для изображений. 

### Автоматизация запуска сервера модели:
Через скрипт
```bash
sudo nano /etc/systemd/system/llama-cpp.service
```
Вносим:
```sh
[Unit]
Description=Llama.cpp Server
After=network.target

[Service]
Type=simple
WorkingDirectory=/home/user/llama.cpp
ExecStart=/home/user/llama.cpp/build/bin/llama-server -m /home/user/llama.cpp/Qwen3.5-0.8B-Q4_K_M.gguf --mmproj /home/user/llama.cpp/mmproj-F16_0_8.gguf -ngl 99 -c 32768 --host 0.0.0.0 --port 8080
Restart=always

[Install]
WantedBy=default.target
```
Выставляем автозапуск и запускаем. 
```bash
sudo systemctl daemon-reload
sudo systemctl enable llama-cpp.service
sudo systemctl start llama-cpp.service
```

## Инфрастуктура

### Во всех sh-файлах и инструкциях проверить текст server-ip -- нужно заменять на свой. Его можно определить через
```bash
ip a
```

### Клонирование репозитория

```bash
cd ~
git clone https://github.com/danil1online/gitlab_ce_ai_study.git gitlab
cd ~/gitlab
```

### [Докер-файл](docker-compose.yml) 
Проверяем содержание
```bash
nano docker-compose.yml
```

Порт SSH внутри GitLab выставлен на 2222, чтобы не конфликтовать с системным SSH.

Настроен внешний ip (на vds/vps поднят vpn) на основной порт 80. Порты 80, 2222, порт для llama-server 8080 в тестовой конфигурации проброшены от vds/vps (или начинаются мелкие проблемы, например, с тем, что клонировать из меню репозитория сервис предлагает с внутреннего адреса ПК) 

 -> `Ctrl+X`

### Использованая версия gitlab-ce: 18.9

Внутри ./gitlab создаем каталоги
```bash
mkdir ./config
mkdir ./logs
mkdir ./data
mkdir ./runner-config
```

Запуск:
```bash
docker compose up -d
```

## Доступ и начальная настройка

### Найти пароль root:
```bash
docker exec -it gitlab grep 'Password:' /etc/gitlab/initial_root_password
```

### Открыть в браузере: http://Server-IP

Зайти как root + найденный пароль, сразу задать новый пароль.

### Создать personal access token для root

Зайти под root → Preferences → Personal Access Tokens (или User Settings → Access Tokens).

http://Server-IP/-/user_settings/personal_access_tokens?page=1&state=active&sort=expires_asc

Создать токен с правами api (название любое), сохранить значение, например GL_TOKEN.

## Создание студентов с нужными логинами

Создание учетных записей, добавление их в группу.

Формат логина: student_{группа}_{порядковый номер} Примеры: student_pia_01, student_ista_12, student_istb_30, student_ita_07.

Самый удобный путь — через GitLab API и скрипт.

Реализован в [create_students.sh](create_students.sh)
```bash
chmod +x create_students.sh
./create_students.sh
```

## Регистрация GitLab Runner

### Подготовка GitLab -- получение токена

Перейти в Admin Area (иконка гаечного ключа вверху справа или в меню слева).

Выбрать CI/CD -> Runners.

Нажмите кнопку New instance runner (в новых версиях). 

Заполните все поля и запомните tag (например, docker_runner).

Скопируйте сформированный токен ("glpat-"). 

### Подготовка runnera 
```bash
docker exec -it gitlab-runner gitlab-runner register
```
Пример вводных данных:
```bash
Runtime platform                                    arch=amd64 os=linux pid=17 revision=07e534ba version=18.9.0
Running in system-mode.                                                                            
Enter the GitLab instance URL (for example, https://gitlab.com/):
"http://Server-IP"
Enter the registration token:
"glrt-...................."
Verifying runner... is valid                        correlation_id=01KKCHZSJF4KRVPQVC8A8464QM runner=Lhu0hm2sC runner_name=12f58acb964c
Enter a name for the runner. This is stored only in the local config.toml file:
[12f58acb964c]: "docker-runner"
Enter an executor: virtualbox, docker, docker-windows, shell, parallels, docker+machine, kubernetes, docker-autoscaler, instance, custom, ssh:
"docker"
Enter the default Docker image (for example, ruby:3.3):
"curlimages/curl:latest"
Runner registered successfully. Feel free to start it, but if it's running already the config should be automatically reloaded!
Configuration (with the authentication token) was saved in "/etc/gitlab-runner/config.toml"
```

### Свой [образ для runner'а](Dockerfile.runner)
Сразу собирает подходящий набор инструментов для парсинга и обработки *.ipynb:

```bash
docker build -t my-runner-tools:latest -f Dockerfile.runner .
```

### Проверить и изменить

```bash
docker exec -it gitlab-runner bash
apt update
apt install nano
nano /etc/gitlab-runner/config.toml
```
* вверху
```sh
 "concurrent = 1"
```

* в секции runners.docker
```sh
    tls_verify = false
    image = "my-runner-tools:latest"  # Укажите ваш будущий образ как дефолтный
    pull_policy = ["if-not-present"] # ГЛАВНОЕ: сначала искать образ локально
    privileged = false
    disable_entrypoint_overwrite = false
    oom_kill_disable = false
    disable_cache = false
    volumes = ["/cache"]
    # ... остальное без изменений
```
  -> `Ctrl+O` -> `Ctrl+X`

```bash
exit
docker restart gitlab-runner
```

# Дополнительно

## [cleanup_repos.sh](cleanup_repos.sh) 
Удобный и безопасный скрипт, который:
- удаляет все репозитории всех студентов
- удаляет репозитории студентов выбранной группы
- удаляет репозитории одного конкретного студента
Для использования
```bash
sudo apt install jq
chmod +x cleanup_repos.sh
./cleanup_repos.sh
```

## Удалить пользователей, кроме основных, но включая препода
```bash
sudo apt install jq
chmod +x delete_all_users.sh
./delete_all_users.sh
```


# Инструкция для студентов:
## Войти в http://Server-IP, например, с учетными данными student_ista_01 / ChangeMe123!
## Создать проект:
1. Справа вверху нажать на иконку "+" - "New project/repository" - "Create from template" - "GitLab CI/CD components" (внизу) - "Use template"
2. Заполнить "Project name" - "ist_lab{x}", где {x} - номер работы.
3. В "Project URL" - "Pick a group or namespace" выбрать "Users" : имя пользователя (в данном примере student_ista_01).
4. В "Project description (optional)" - "ist_lab{x}", где {x} - номер работы.
5. В "Visibility Level" - "Public"
6. "Create project"
## Изменить алгоритм проверки CI/CD
1. Нажать на файле ".gitlab-ci.yml", в новом окне нажать кнопку "Edit" - "Edit single file"
2. Заменить текст в открывшемся окне на
```sh
stages:
  - ai

ai_review:
  stage: ai
  tags:
    - docker_runner
  image: my-runner-tools:latest
  script:
    - echo "Поиск самого свежего блокнота..."
    # ls -t сортирует от новых к старым, head -n 1 берет самый первый
    - NB_FILE=$(ls -t *.ipynb 2>/dev/null | head -n 1 || true)
    - |
      if [ -z "$NB_FILE" ]; then
        echo "Файл .ipynb не найден. Анализ не требуется."
        exit 0
      fi
    - |
      echo "Анализирую последний измененный файл: $NB_FILE"
    
    # Извлекаем картинку (мягкий режим)
    - |
      IMAGE_DATA=$(grep -oE '"image/png": "[^"]+"' "$NB_FILE" | head -n 1 | cut -d'"' -f4 || echo "")
    
    # Подготовка текста (первые 1500 строк кода без мусора)
    - |
      head -n 1500 "$NB_FILE" | \
      sed -E 's/"image\/(png|jpeg)": "[^"]+"/"image_hidden"/g' | \
      sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\r' | tr '\n' ' ' > cleaned_code.txt

    # Сборка JSON
    - |
      printf '{"model":"Qwen3.5-0.8B","messages":[{"role":"user","content":[' > payload.json
    - |
      if [ -n "$IMAGE_DATA" ]; then
        printf '{"type": "image_url", "image_url": {"url": "data:image/png;base64,%s"}},' "$IMAGE_DATA" >> payload.json
      fi
    - |
      printf '{"type": "text", "text": "Проанализируй код Jupyter Notebook: ' >> payload.json
    - cat cleaned_code.txt >> payload.json
    - |
      printf '"}]}]}' >> payload.json

    # Отправка на AI сервер
    - |
      curl -s -X POST "http://Server-IP:8080/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -d @payload.json \
        --max-time 180 \
        -o ai_report.json || echo "Ошибка связи с моделью"

    - |
      if [ -f ai_report.json ]; then 
        echo "--- Ответ от AI ---"
        cat ai_report.json
      fi
  artifacts:
    paths:
      - ai_report.json
    when: on_success
    expire_in: 1 week
```
2. "Commit changes" - "Commit changes"
3. Напротив надписи "Edit .gitlab-ci.yml" появится сначала значек синего кружка с незаполненным сектором. Значит задача проверки выполняется. Дожидаемся окончания ("Passed" или аналогичное). 
## Использование автопроверки. 
1. Загружаем в проект ipynb-файл для проверки - в корень проекта, например, для преподавателя {prepod} и первой работы {1} http://<Server-IP>/prepod/ist_lab1/
Нажимаем "+" - "Upload file" - "upload" - выбрать файл *.ipynb - "Commit changes". Автоматически запустится повторная проверка. 
2. Переходим по адресу, соответствующему учетной записи, например, для преподавателя {prepod} и первой работы {1}
http://Server-IP/prepod/ist_lab1/-/jobs
Если проверка прошла штатно, в открывшемся то справа в первом из списка пункте будет кнопка "Download artifacts". Ее нужать -- скачается архив, в нем -- "ai_report.json". 
3. Открываем ai_report.json текстовым редактором или перетаскиваем в браузер, например, Google Chrome и в откывшемся окне вверху слева ставим галочку "Автоформатировать". Проверяем "content" - должно соответствовать проверяемому файлу. Корректируем форматирование, вносим в отчет по практической работе.   

# License

This project is licensed under the [CC-BY 4.0](https://creativecommons.org/licenses/by/4.0/) license. See the [LICENSE](./LICENSE) file for details.
