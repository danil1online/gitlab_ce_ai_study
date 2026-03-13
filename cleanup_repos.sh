#!/usr/bin/env bash

GITLAB_URL="http://server-ip" # Заменить на свой
TOKEN="glpat-...." ###########################################TOKEN="glpat-XXXXXXXXXXXX"

confirm() {
  read -p "Вы уверены? (yes/no): " ans
  if [[ "$ans" != "yes" ]]; then
    echo "Отменено."
    exit 1
  fi
}

delete_projects_of_user() {
  local username="$1"

  echo "Ищу пользователя $username..."

  user_id=$(curl --silent --header "PRIVATE-TOKEN: $TOKEN" \
    "$GITLAB_URL/api/v4/users?search=$pattern&per_page=1000" | jq -r '.[0].id')

  if [[ "$user_id" == "null" || -z "$user_id" ]]; then
    echo "Пользователь $username не найден."
    return
  fi

  echo "Найден user_id=$user_id. Получаю список проектов..."

  project_ids=$(curl --silent --header "PRIVATE-TOKEN: $TOKEN" \
    "$GITLAB_URL/api/v4/users/$user_id/projects" | jq -r '.[].id')

  if [[ -z "$project_ids" ]]; then
    echo "У пользователя $username нет проектов."
    return
  fi

  echo "Будут удалены проекты: $project_ids"
  confirm

  for pid in $project_ids; do
    echo "Удаляю проект $pid..."
    curl --silent --show-error --fail \
      --request DELETE \
      --header "PRIVATE-TOKEN: $TOKEN" \
      "$GITLAB_URL/api/v4/projects/$pid"
  done
}

get_all_usernames_by_pattern() {
  local pattern="$1"
  local page=1
  local result=""
  local page_result=""

  while true; do
    page_result=$(curl --silent --header "PRIVATE-TOKEN: $TOKEN" \
      "$GITLAB_URL/api/v4/users?search=$pattern&per_page=100&page=$page" \
      | jq -r '.[].username')

    # если страница пустая — выходим
    if [[ -z "$page_result" ]]; then
      break
    fi

    result+="$page_result"$'\n'
    page=$((page + 1))
  done

  echo "$result"
}

delete_by_pattern() {
  local pattern="$1"
  echo "Поиск пользователей по шаблону: $pattern"

  usernames=$(get_all_usernames_by_pattern "$pattern")

  if [[ -z "$usernames" ]]; then
    echo "Нет пользователей по шаблону '$pattern'"
    exit 0
  fi

  echo "Найдены пользователи:"
  echo "$usernames"
  confirm

  for u in $usernames; do
    delete_projects_of_user "$u"
  done
}


echo "Выберите действие:"
echo "1) Удалить репозитории ВСЕХ студентов (student_*)"
echo "2) Удалить репозитории студентов группы (pia, ista, istb, pa)"
echo "3) Удалить репозитории одного студента"
read -p "Ваш выбор: " choice

case $choice in
  1)
    delete_by_pattern "student_"
    ;;
  2)
    read -p "Введите имя группы: " group
    delete_by_pattern "student_${group}_"
    ;;
  3)
    read -p "Введите логин студента: " login
    delete_projects_of_user "$login"
    ;;
  *)
    echo "Неверный выбор."
    ;;
esac
