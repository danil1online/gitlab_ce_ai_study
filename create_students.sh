#!/usr/bin/env bash

set -e

GITLAB_URL="http://193.124.118.93"
TOKEN="glpat-TOJ9flfvPgLrz_JrvliaOG86MQp1OjEH.01.0w1j9q580"

GROUP_NAME="students"
GROUP_PATH="students"

# ---------- ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ ----------

api() {
  curl --silent --show-error --fail \
    --header "PRIVATE-TOKEN: $TOKEN" \
    "$@"
}

upload_file_to_project() {
  local project_id="$1"
  local local_path="$2"
  local target_path="$3"

  echo "Загружаю $local_path → $target_path в проект $project_id"

  if [ ! -f "$local_path" ]; then
    echo "Файл $local_path не найден!"
    return 1
  fi

  CONTENT=$(cat "$local_path")

  # Пытаемся создать файл
  CREATE_RESPONSE=$(curl --silent --show-error --fail \
    --request POST \
    --header "PRIVATE-TOKEN: $TOKEN" \
    --data-urlencode "branch=main" \
    --data-urlencode "content=$CONTENT" \
    --data-urlencode "commit_message=Add $target_path" \
    "$GITLAB_URL/api/v4/projects/$project_id/repository/files/$target_path" 2>&1)

  if echo "$CREATE_RESPONSE" | grep -q "file_exists"; then
    echo "Файл уже существует, обновляю..."
    curl --silent --show-error --fail \
      --request PUT \
      --header "PRIVATE-TOKEN: $TOKEN" \
      --data-urlencode "branch=main" \
      --data-urlencode "content=$CONTENT" \
      --data-urlencode "commit_message=Update $target_path" \
      "$GITLAB_URL/api/v4/projects/$project_id/repository/files/$target_path"
  else
    echo "Файл успешно создан."
  fi
}


create_group() {
  echo "Создаю (или получаю) группу $GROUP_NAME..."

  GROUP_ID=$(curl --silent --header "PRIVATE-TOKEN: $TOKEN" \
    --data "name=$GROUP_NAME" \
    --data "path=$GROUP_PATH" \
    "$GITLAB_URL/api/v4/groups" | jq -r '.id')

  if [[ "$GROUP_ID" == "null" || -z "$GROUP_ID" ]]; then
    echo "Группа уже существует, получаю ID..."
    GROUP_ID=$(curl --silent --header "PRIVATE-TOKEN: $TOKEN" \
      "$GITLAB_URL/api/v4/groups/$GROUP_PATH" | jq -r '.id')
  fi

  echo "GROUP_ID = $GROUP_ID"
}

create_user() {
  local username="$1"
  local email="$2"
  local name="$3"

  echo "Создаю (или получаю) пользователя: $username"

  USER_ID=$(curl --silent --header "PRIVATE-TOKEN: $TOKEN" \
    --data "email=${email}" \
    --data "username=${username}" \
    --data "name=${name}" \
    --data "password=ChangeMe123!" \
    --data "skip_confirmation=true" \
    "$GITLAB_URL/api/v4/users" | jq -r '.id')

  if [[ "$USER_ID" == "null" || -z "$USER_ID" ]]; then
    echo "Пользователь уже существует, получаю ID..."
    USER_ID=$(curl --silent --header "PRIVATE-TOKEN: $TOKEN" \
      "$GITLAB_URL/api/v4/users?username=$username" | jq -r '.[0].id')
  fi

  echo "USER_ID = $USER_ID"

  echo "Добавляю $username в группу $GROUP_NAME как Developer..."
  curl --silent --show-error --fail \
    --request POST \
    --header "PRIVATE-TOKEN: $TOKEN" \
    --data "user_id=$USER_ID" \
    --data "access_level=30" \
    "$GITLAB_URL/api/v4/groups/$GROUP_ID/members" \
    >/dev/null || echo "Возможно, уже в группе."
}

create_group_students() {
  local group="$1"
  local count="$2"

  for i in $(seq -w 1 "$count"); do
    local username="student_${group}_${i}"
    local email="${username}@example.local"
    local name="Student ${group^^} ${i}"
    create_user "$username" "$email" "$name"
  done
}

create_project() {
  local name="$1"
  local path="$2"

  echo "Создаю (или получаю) проект $name..."

  PROJECT_ID=$(curl --silent --show-error --fail \
    --header "PRIVATE-TOKEN: $TOKEN" \
    --data "name=$name" \
    --data "path=$path" \
    --data "namespace_id=$GROUP_ID" \
    "$GITLAB_URL/api/v4/projects" | jq -r '.id')

  if [[ "$PROJECT_ID" == "null" || -z "$PROJECT_ID" ]]; then
    echo "Проект уже существует, получаю ID..."
    PROJECT_ID=$(curl --silent --header "PRIVATE-TOKEN: $TOKEN" \
      "$GITLAB_URL/api/v4/projects?search=$path" | jq -r '.[] | select(.path=="'"$path"'") | .id' | head -n1)
  fi

  echo "PROJECT_ID($name) = $PROJECT_ID"
  echo "$PROJECT_ID"
}

# ---------- ОСНОВНОЙ СЦЕНАРИЙ ----------

if ! command -v jq >/dev/null 2>&1; then
  echo "Нужен jq: sudo apt install jq"
  exit 1
fi

create_group

echo "Создаю студентов..."
create_group_students "pia" 30
create_group_students "ista" 30
create_group_students "istb" 30
create_group_students "ita" 30

echo "Создаю преподавателя..."
create_user "prepod" "prepod@example.local" "Prepodavatel"

echo "Готово."
echo "Группа: $GROUP_PATH"