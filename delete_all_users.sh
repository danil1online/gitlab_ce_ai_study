#!/usr/bin/env bash

GITLAB_URL="http://193.124.118.93"
TOKEN="glpat-TOJ9flfvPgLrz_JrvliaOG86MQp1OjEH.01.0w1j9q580"

# Получение всех пользователей с пагинацией
get_all_users() {
  local page=1
  local result=""
  local page_result=""

  while true; do
    page_result=$(curl --silent --header "PRIVATE-TOKEN: $TOKEN" \
      "$GITLAB_URL/api/v4/users?per_page=100&page=$page" \
      | jq -r '.[] | "\(.id) \(.username)"')

    [[ -z "$page_result" ]] && break

    result+="$page_result"$'\n'
    page=$((page + 1))
  done

  echo "$result"
}

# Удаление пользователя по ID
delete_user() {
  local id="$1"
  local username="$2"

  echo "Удаляю пользователя: $username (id=$id)"

  curl --silent --show-error --fail \
    --request DELETE \
    --header "PRIVATE-TOKEN: $TOKEN" \
    "$GITLAB_URL/api/v4/users/$id"
}

echo "Получаю список всех пользователей..."
users=$(get_all_users)

echo "Найдены пользователи:"
echo "$users"

echo
echo "Эти пользователи будут удалены, кроме root и GitLabDuo."
echo "Продолжить? (yes/no)"
read ans
[[ "$ans" != "yes" ]] && echo "Отменено." && exit 1

while read -r line; do
  [[ -z "$line" ]] && continue

  id=$(echo "$line" | awk '{print $1}')
  username=$(echo "$line" | awk '{print $2}')

  # Пропускаем root
  [[ "$username" == "root" ]] && continue

  # Пропускаем GitLabDuo
  [[ "$username" == "GitLabDuo" ]] && continue

  delete_user "$id" "$username"

done <<< "$users"

echo "Готово. Все пользователи (кроме root и GitLabDuo) удалены."
