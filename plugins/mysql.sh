#!/bin/bash
#
# mysql.sh
#
# Author: Matteo Cerutti <matteo.cerutti@hotmail.co.uk>
#

test -s $(dirname $0)/mysql.cfg && . $(dirname $0)/mysql.cfg

# source some useful mysql helpers
test -r $(dirname $0)/mysql_helpers.sh && . $(dirname $0)/mysql_helpers.sh || exit 1

function showhelp() {
  echo -n "Usage: `basename $0` [<opts>] "
  case $1 in
    "replication")
      case $2 in
        "checksum")
          echo "$1 $2 <db.table>"
          ;;

        *)
          echo "$1 <last_errno|lag|io_thread|sql_thread|sync_log_pos|discovery|checksum>"
      esac
      ;;

    *)
      echo "<uptime|threads|slowqueries|questions|qps|ping|opens|opentables|flushtables|bytes_sent|bytes_received|com_*|replication>"
  esac

  echo
  echo "  Options:"
  echo "  --master-host <host>                MySQL master host (default: \$MYSQL_MASTER_HOST)"
  echo "  --master-user <user>                MySQL master user (default: \$MYSQL_MASTER_USER)"
  echo "  --master-password <password>        MySQL master password (default: \$MYSQL_MASTER_PASSWORD)"
  echo "  --slave-host <host>                 MySQL slave host (default: \$MYSQL_SLAVE_HOST)"
  echo "  --slave-user <user>                 MySQL slave user (default: \$MYSQL_SLAVE_USER)"
  echo "  --slave-password <password>         MySQL slave password (default: \$MYSQL_SLAVE_PASSWORD)"
  echo "  --checksum-retry <N>                Maximum number of retries when comparing master and slave checksums (default: \$MYSQL_CHECKSUM_RETRY)"
  echo "  --verbose                           Be verbose"
  echo

  exit 1
}

which mysqladmin &>/dev/null && MYSQLADMIN_BIN=$(which mysqladmin) || {
  test -e /usr/bin/mysqladmin && MYSQLADMIN_BIN=/usr/bin/mysqladmin || { echo "Unable to locate mysqladmin" >&2; exit 1; }
}
test ! -x $MYSQLADMIN_BIN && { echo "Unable to execute $MYSQLADMIN_BIN" >&2; exit 1; }

slave_host=${MYSQL_SLAVE_HOST:-localhost}
slave_user=$MYSQL_SLAVE_USER
slave_password=$MYSQL_SLAVE_PASSWORD
master_host=$MYSQL_MASTER_HOST
master_user=$MYSQL_MASTER_USER
master_password=$MYSQL_MASTER_PASSWORD
checksum_retry=${MYSQL_CHECKSUM_RETRY:-3}
verbose=0

while :
do
  case $1 in
    -h | --help)
      showhelp
      ;;

    --master-host)
      master_host=$2
      shift 2
      ;;

    --master-user)
      master_user=$2
      shift 2
      ;;

    --master-password)
      master_password=$2
      shift 2
      ;;

    --slave-host)
      slave_host=$2
      shift 2
      ;;

    --slave-user)
      slave_user=$2
      shift 2
      ;;

    --slave-password)
      slave_password=$2
      shift 2
      ;;

    --checksum-retry)
      checksum_retry=$2
      shift 2
      ;;

    --verbose)
      verbose=1
      shift 1
      ;;

    --)
      shift
      break
      ;;

    -*)
      echo "Unknown option '$1'"
      showhelp
      ;;

    *)
      break
  esac
done

# mysql client/admin default options
mysql_opts="--defaults-file=$MYCNF_PATH"

case $1 in
  "uptime")
    $MYSQLADMIN_BIN $mysql_opts status | cut -f2 -d':' | cut -f1 -d'T' | sed -e 's/^\s*//'
    ;;

  "threads")
    $MYSQLADMIN_BIN $mysql_opts status | cut -f3 -d':' | cut -f1 -d'Q' | sed -e 's/^\s*//'
    ;;

  "slowqueries")
    $MYSQLADMIN_BIN $mysql_opts status | cut -f5 -d':' | cut -f1 -d'O' | sed -e 's/^\s*//'
    ;;

  "questions")
    $MYSQLADMIN_BIN $mysql_opts status | cut -f4 -d':' | cut -f1 -d'S' | sed -e 's/^\s*//'
    ;;

  "qps")
    $MYSQLADMIN_BIN $mysql_opts status | cut -f9 -d':' | sed -e 's/^\s*//'
    ;;

  "ping")
    $MYSQLADMIN_BIN $mysql_opts status | grep alive | wc -l
    ;;

  "opens")
    $MYSQLADMIN_BIN $mysql_opts status | cut -f6 -d':' | cut -f1 -d'F' | sed -e 's/^\s*//'
    ;;

  "opentables")
    $MYSQLADMIN_BIN $mysql_opts status | cut -f8 -d':' | cut -f1 -d'Q' | sed -e 's/^\s*//'
    ;;

  "flushtables")
    $MYSQLADMIN_BIN $mysql_opts status | cut -f7 -d':' | cut -f1 -d'O' | sed -e 's/^\s*//'
    ;;

  com_* | "bytes_received" | "bytes_sent")
    mysql_batch_query "$mysql_opts" "show global status" | egrep -i "^$1\s+" | awk '{ print $2 }' | sed -e 's/^\s*//'
    ;;

  "replication" | "slave")
    if [ ! -e $MYCNF_PATH ]; then
      test -z "$slave_host" && { echo "Need to specify the MySQL slave host" >&2; showhelp; }
      test -z "$slave_user" && { echo "Need to specify the MySQL slave user" >&2; showhelp; }

      slave_opts="-u $slave_user --password=$slave_password -h $slave_host"
    else
      slave_opts="--defaults-file=$MYCNF_PATH"
    fi

    case $2 in
      "discovery")
        while read line; do
          if [ -n "$line" ]; then
            key=$(echo "$line" | awk -F ':' '{ print $1 }')
            value=$(echo "$line" | awk -F ':' '{ print $2 }' | sed -e 's/\s*//g')

            case $key in
              "Replicate_Do_DB")
                for db in $(echo "$value" | tr ',' ' '); do
                  test -z "$repicate_do_db" && replicate_do_db="$db" || replicate_do_db="$replicate_do_db $db"
                done
                ;;

              "Replicate_Ignore_DB")
                for db in $(echo "$value" | tr ',' ' '); do
                  test -z "$replicate_ignore_db" && replicate_ignore_db="$db" || replicate_ignore_db="$replicate_ignore_db $db"
                done
                ;;

              "Replicate_Do_Table")
                for table in $(echo "$value" | tr ',' ' '); do
                  test -z "$replicate_do_table" && replicate_do_table="$table" || replicate_do_table="$replicate_do_table $table"
                done
                ;;

              "Replicate_Ignore_Table")
                for table in $(echo "$value" | tr ',' ' '); do
                  test -z "$replicate_ignore_table" && replicate_ignore_table="$table" || replicate_ignore_table="$replicate_ignore_table $table"
                done
                ;;

              "Replicate_Wild_Do_Table")
                for table in $(echo "$value" | tr ',' ' '); do
                  test -z "$replicate_wild_do_table" && replicate_wild_do_table="$table" || replicate_wild_do_table="$replicate_wild_do_table $table"
                done
                ;;

              "Replicate_Wild_Ignore_Table")
                for table in $(echo "$value" | tr ',' ' '); do
                  test -z "$replicate_wild_ignore_table" && replicate_wild_ignore_table="$table" || replicate_wild_ignore_table="$replicate_wild_ignore_table $table"
                done
            esac
          fi
        done <<EOF
$(mysql_batch_query "$slave_opts" 'SHOW SLAVE STATUS\G' | sed -e 's/^\s*//g' | egrep -i '^Replicate_')
EOF

        do_db_query=
        if [ -n "$replicate_do_db" ]; then
          for db in $replicate_do_db; do
            test -z "$do_db_query" && do_db_query="TABLE_SCHEMA = '$db'" || do_db_query="$do_db_query OR TABLE_SCHEMA = '$db'"
          done
        fi

        ignore_db_query=
        if [ -n "$replicate_ignore_db" ]; then
          for db in $replicate_ignore_db; do
            test -z "$ignore_db_query" && ignore_db_query="TABLE_SCHEMA != '$db'" || ignore_db_query="$ignore_db_query AND TABLE_SCHEMA != '$db'"
          done
        fi

        do_table_query=
        if [ -n "$replicate_do_table" ]; then
          for dbtable in $replicate_do_table; do
            db=$(echo "$dbtable" | cut -d '.' -f 1)
            table=$(echo "$dbtable" | cut -d '.' -f 2)
            test -z "$do_table_query" && do_table_query="(TABLE_SCHEMA = '$db' AND TABLE_NAME = '$table')" || do_table_query="$do_table_query OR (TABLE_SCHEMA = '$db' AND TABLE_NAME = '$table')"
          done
        fi

        ignore_table_query=
        if [ -n "$replicate_ignore_table" ]; then
          for dbtable in $replicate_ignore_table; do
            db=$(echo "$dbtable" | cut -d '.' -f 1)
            table=$(echo "$dbtable" | cut -d '.' -f 2)
            test -z "$replicate_ignore_table" && ignore_table_query="(TABLE_SCHEMA != '$db' AND TABLE_NAME != '$table')" || ignore_table_query="$ignore_table_query AND (TABLE_SCHEMA != '$db' AND TABLE_NAME != '$table')"
          done
        fi

        wild_do_table_query=
        if [ -n "$replicate_wild_do_table" ]; then
          for dbtable in $replicate_wild_do_table; do
            db=$(echo "$dbtable" | cut -d '.' -f 1)
            table=$(echo "$dbtable" | cut -d '.' -f 2)
            test -z "$wild_do_table_query" && wild_do_table_query="(TABLE_SCHEMA LIKE '$db' AND TABLE_NAME LIKE '$table')" || wild_do_table_query="$wild_do_table_query OR (TABLE_SCHEMA LIKE '$db' AND TABLE_NAME LIKE '$table')"
          done
        fi

        wild_ignore_table_query=
        if [ -n "$replicate_wild_ignore_table" ]; then
          for dbtable in $replicate_wild_ignore_table; do
            db=$(echo "$dbtable" | cut -d '.' -f 1)
            table=$(echo "$dbtable" | cut -d '.' -f 2)
            test -z "$wild_ignore_table_query" && wild_ignore_table_query="(TABLE_SCHEMA NOT LIKE '$db' AND TABLE_NAME NOT LIKE '$table')" || wild_ignore_table_query="$wild_ignore_table_query AND (TABLE_SCHEMA NOT LIKE '$db' AND TABLE_NAME NOT LIKE '$table')"
          done
        fi

        # rules
        # 1. replicate-do-db and replicate-ignore-db
        # 2. replicate-do-table and replicate-wild-do-table
        # 2. replicate-ignore-table and replicate-wild-ignore-table

        do_query=
        if [ -n "$do_db_query" ]; then
          do_query="(($do_db_query)"
        fi

        if [ -n "$do_table_query" ]; then
          test -z "$do_query" && do_query="($do_table_query)" || do_query="$do_query OR ($do_table_query)"
        fi

        if [ -n "$wild_do_table_query" ]; then
          test -z "$do_query" && do_query="($wild_do_table_query)" || do_query="$do_query OR ($wild_do_table_query)"
        fi

        ignore_query=
        if [ -n "$ignore_db_query" ]; then
          ignore_query="($ignore_db_query)"
        fi

        if [ -n "$ignore_table_query" ]; then
          test -z "$ignore_query" && ignore_query="($ignore_table_query)" || ignore_query="$ignore_query AND ($ignore_table_query)"
        fi

        if [ -n "$wild_ignore_table_query" ]; then
          test -z "$ignore_query" && ignore_query="($wild_ignore_table_query)" || ignore_query="$ignore_query AND ($wild_ignore_table_query)"
        fi

        # build the query
        test -n "$do_query" && query="AND ($do_query)"
        if [ -n "$ignore_query" ]; then
          test -z "$query" && query="AND ($ignore_query)" || query="$query AND ($ignore_query)"
        fi

        if [ $verbose -eq 1 ]; then
          echo "replicate_do_db: $replicate_do_db"
          echo "replicate_ignore_db: $replicate_ignore_db"
          echo "replicate_do_table: $replicate_do_table"
          echo "replicate_ignore_table: $replicate_ignore_table"
          echo "replicate_wild_do_table: $replicate_wild_do_table"
          echo "replicate_wild_ignore_table: $replicate_wild_ignore_table"
          echo "do_db_query: $do_db_query"
          echo "ignore_db_query: $ignore_db_query"
          echo "do_table_query: $do_table_query"
          echo "ignore_table_query: $ignore_table_query"
          echo "wild_do_table_query: $wild_do_table_query"
          echo "wild_ignore_table_query: $wild_ignore_table_query"
          echo "query: $query"
        fi

        count=0
        echo "{"
        echo "  \"data\": ["
        while read schema; do
          if [ -n "$schema" ]; then
            database_name=$(echo "$schema" | awk '{ print $1 }')
            table_name=$(echo "$schema" | awk '{ print $2 }')
            [ $count -gt 0 ] && echo "    },"
            echo "    {"
            echo "        \"{#DATABASE_NAME}\": \"$database_name\","
            echo "        \"{#TABLE_NAME}\": \"$table_name\""
            count=$((count+1))
          fi
        done <<EOF
$(mysql_batch_query "$slave_opts" "SELECT TABLE_SCHEMA,TABLE_NAME FROM information_schema.tables WHERE TABLE_TYPE != 'VIEW' $query")
EOF
        [ $count -gt 0 ] && echo "    }"
        echo "  ]"
        echo "}"
        ;;

      "checksum")
        target=$3

        test -z "$master_host" && { echo "Need to specify the MySQL master host" >&2; showhelp; }
        test -z "$master_user" && { echo "Need to specify the MySQL master user" >&2; showhelp; }

        test -z "$target" && { echo "Need to specify one target to checksum" >&2; showhelp; }

        master_opts="-u $master_user --password=$master_password -h $master_host"

        retry_count=0
        while [ $retry_count -lt $checksum_retry ]; do
          master_checksum=$(mysql_batch_query "$master_opts" "CHECKSUM TABLE $target" | awk '{ print $2 }')
          slave_checksum=$(mysql_batch_query "$slave_opts" "CHECKSUM TABLE $target" | awk '{ print $2 }')

          if [ $verbose -eq 1 ]; then
            echo "master_checksum: $master_checksum"
            echo "slave_checksum: $slave_checksum"
          fi

          if [[ "$master_checksum" != "NULL" && "$slave_checksum" != "NULL" ]]; then
            if [ $master_checksum -ne $slave_checksum ]; then
              sleep 1
            else
              break
            fi
          fi

          retry_count=$((retry_count+1))
          [ $verbose -eq 1 ] && echo "retrying ($retry_count/$checksum_retry)"
        done

        if [[ "$master_checksum" != "NULL" && "$slave_checksum" != "NULL" ]]; then
          [ $master_checksum -eq $slave_checksum ] && echo 0 || echo 1
        else
          # absent
          echo -1
        fi
        ;;

      "last_errno")
        errno=$(mysql_batch_query "$slave_opts" "show slave status\G" | grep -i "Last_Errno:" | sed -e 's/\s*//g' | awk -F ':' '{ print $2 }')
        test -n "$errno" && echo $errno
        ;;

      "lag")
        lag=$(mysql_batch_query "$slave_opts" "show slave status\G" | grep -i "Seconds_Behind_Master:" | sed -e 's/\s*//g' | awk -F ':' '{ print $2 }' | sed -e 's/^NULL$/-1/')
        test -n "$lag" && echo $lag
        ;;

      "io_thread")
        io_thread_status=$(mysql_batch_query "$slave_opts" "show slave status\G" | grep -i "Slave_IO_Running:" | sed -e 's/\s*//g' | tr '[A-Z]' '[a-z]' | awk -F ':' '{ print $2 }')

        case $io_thread_status in
          "yes") echo 0 ;;
          "no") echo 1 ;;
        esac
        ;;

      "sql_thread")
        sql_thread_status=$(mysql_batch_query "$slave_opts" "show slave status\G" | grep -i "Slave_SQL_Running:" | sed -e 's/\s*//g' | tr '[A-Z]' '[a-z]' | awk -F ':' '{ print $2 }')

        case $sql_thread_status in
          "yes") echo 0 ;;
          "no") echo 1 ;;
        esac
        ;;

      "sync_log_pos")
        positions=$(mysql_batch_query "$slave_opts" "show slave status\G" | egrep -i "(Read_Master_Log_Pos|Exec_Master_Log_Pos):" | awk -F ':' '{ print $2 }' | xargs)
        read_master_log_pos=$(echo "$positions" | cut -d ' ' -f 1)
        exec_master_log_pos=$(echo "$positions" | cut -d ' ' -f 2)

        if [[ -n "$read_master_log_pos" && -n "$exec_master_log_pos" ]]; then
          [ $read_master_log_pos -eq $exec_master_log_pos ] && echo 0 || echo 1
        fi
        ;;

      *)
        showhelp $1
    esac
    ;;

  *)
    showhelp
esac

exit 0
