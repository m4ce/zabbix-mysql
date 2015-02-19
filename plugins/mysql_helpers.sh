#!/bin/bash
#
# Description: helpers for MySQL 
#
# Author: Matteo Cerutti <matteo.cerutti@hotmail.co.uk>
#

MYCNF_PATH="$ZBX_HOME/.my.cnf"

# default timeout in seconds
MYSQL_TIMEOUT=${MYSQL_TIMEOUT:-5}

# client options
MYSQL_OPTS="--connect_timeout=$MYSQL_TIMEOUT"

which mysql &>/dev/null && MYSQL_BIN=$(which mysql) || {
  test -e /usr/bin/mysql && MYSQL_BIN=/usr/bin/mysql || { echo "Unable to locate mysql" >&2; exit 1; }
}
test ! -x $MYSQL_BIN && { echo "Unable to execute $MYSQL_BIN" >&2; exit 1; }

#
# performs a query in batch mode
#
function mysql_batch_query() {
  local opts=$1
  local query=$2

  $MYSQL_BIN $opts $MYSQL_OPTS --batch --skip-column-names -e "$query"
}
