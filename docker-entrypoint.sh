#!/bin/bash
set -eu

cd /var/www/html

# usage: file_env VAR [DEFAULT]
#    ie: file_env 'XYZ_DB_PASSWORD' 'example'
# (will allow for "$XYZ_DB_PASSWORD_FILE" to fill in the value of
#  "$XYZ_DB_PASSWORD" from a file, especially for Docker's secrets feature)
file_env() {
	local var="$1"
	local fileVar="${var}_FILE"
	local def="${2:-}"
	if [ "${!var:-}" ] && [ "${!fileVar:-}" ]; then
		echo >&2 "error: both $var and $fileVar are set (but are exclusive)"
		exit 1
	fi
	local val="$def"
	if [ "${!var:-}" ]; then
		val="${!var}"
	elif [ "${!fileVar:-}" ]; then
		val="$(< "${!fileVar}")"
	fi
	export "$var"="$val"
	unset "$fileVar"
}

if [[ "$1" == apache2* ]] || [ "$1" == php-fpm ]; then
	file_env 'QUEXF_DB_HOST' 'mysql'
    file_env 'QUEXF_FORMS_DIRECTORY' '/forms/'
    file_env 'QUEXF_IMAGES_DIRECTORY' '/images/'
	file_env 'QUEXF_ADMIN_PASSWORD' 'password'
	# if we're linked to MySQL and thus have credentials already, let's use them
	file_env 'QUEXF_DB_USER' "${MYSQL_ENV_MYSQL_USER:-root}"
	if [ "$QUEXF_DB_USER" = 'root' ]; then
		file_env 'QUEXF_DB_PASSWORD' "${MYSQL_ENV_MYSQL_ROOT_PASSWORD:-}"
	else
		file_env 'QUEXF_DB_PASSWORD' "${MYSQL_ENV_MYSQL_PASSWORD:-}"
	fi
	file_env 'QUEXF_DB_NAME' "${MYSQL_ENV_MYSQL_DATABASE:-quexf}"
	if [ -z "$QUEXF_DB_PASSWORD" ]; then
		echo >&2 'error: missing required QUEXF_DB_PASSWORD environment variable'
		echo >&2 '  Did you forget to -e QUEXF_DB_PASSWORD=... ?'
		echo >&2
		echo >&2 '  (Also of interest might be QUEXF_DB_USER and QUEXF_DB_NAME.)'
		exit 1
	fi

	if [ ! -e /var/www/html/.htaccess ]; then
		echo >&2 "queXF access control not found in $(pwd) - installing now..."

        cat << EOF > /var/www/html/admin/.htaccess
AuthName "queXF"
AuthType Basic
AuthUserFile /opt/quexf/password
AuthGroupFile /opt/quexf/group
require group admin
EOF
       cat << EOF > /var/www/html/client/.htaccess
AuthName "queXF"
AuthType Basic
AuthUserFile /opt/quexf/password
AuthGroupFile /opt/quexf/group
require group client
EOF
       cat << EOF > /var/www/html/.htaccess
AuthName "queXF"
AuthType Basic
AuthUserFile /opt/quexf/password
AuthGroupFile /opt/quexf/group
require group verifier
EOF
		echo >&2 "Complete! queXF access control has been successfully installed to $(pwd)"
	else
        echo >&2 "queXF access control found in $(pwd) - not installing."
	fi

	if [ ! -e /opt/quexf/password ]; then
		echo >&2 "queXF password not found in /opt/quexf/password - creating now..."
        
        htpasswd -c -s -b /opt/quexf/password admin "$QUEXF_ADMIN_PASSWORD"

        cat << EOF > /opt/quexf/group
admin: admin
verifier: admin
client: admin
EOF
		echo >&2 "Complete! queXF admin password created"
	else
        echo >&2 "queXF password found in /opt/quexf - not copying."
	fi

    # Install BaltimoreCyberTrustRoot.crt.pem
    if [ ! -e BaltimoreCyberTrustRoot.crt.pem ]; then
        echo "Downloading BaltimoreCyberTrustroot.crt.pem"
        curl -o BaltimoreCyberTrustRoot.crt.pem -fsL "https://www.digicert.com/CACerts/BaltimoreCyberTrustRoot.crt.pem"
    fi


    chown www-data:www-data -R /images 
    chown www-data:www-data -R images 
    chown www-data:www-data -R /forms
    
	chown www-data:www-data -R /opt/quexf

	# see http://stackoverflow.com/a/2705678/433558
	sed_escape_lhs() {
		echo "$@" | sed -e 's/[]\/$*.^|[]/\\&/g'
	}
	sed_escape_rhs() {
		echo "$@" | sed -e 's/[\/&]/\\&/g'
	}
	php_escape() {
		php -r 'var_export(('$2') $argv[1]);' -- "$1"
	}
	set_config() {
		key="$1"
        value="$(sed_escape_lhs "$2")"
        sed -i "/$key/s/[^,]*/'$value');/2" config.inc.php
	}

	set_config 'DB_HOST' "$QUEXF_DB_HOST"
	set_config 'DB_USER' "$QUEXF_DB_USER"
	set_config 'DB_PASS' "$QUEXF_DB_PASSWORD"
	set_config 'DB_NAME' "$QUEXF_DB_NAME"
    set_config 'SCANS_DIRECTORY' "$QUEXF_FORMS_DIRECTORY"
    set_config 'IMAGES_DIRECTORY' "$QUEXF_IMAGES_DIRECTORY"

	file_env 'QUEXF_DEBUG'
	if [ "$QUEXF_DEBUG" ]; then
		set_config 'DEBUG' 1 
	fi

	file_env 'QUEXF_OCR_ENABLED'
	if [ "$QUEXF_OCR_ENABLED" ]; then
		set_config 'OCR_ENABLED' 'true' 
	fi

	file_env 'QUEXF_HORI_WIDTH_BOX'
	if [ "$QUEXF_HORI_WIDTH_BOX" ]; then
        set_config 'HORI_WIDTH_BOX' "$QUEXF_HORI_WIDTH_BOX" 
	fi

	file_env 'QUEXF_VERT_WIDTH_BOX'
	if [ "$QUEXF_VERT_WIDTH_BOX" ]; then
        set_config 'VERT_WIDTH_BOX' "$QUEXF_VERT_WIDTH_BOX" 
	fi

	file_env 'QUEXF_BARCODE_TLX_PORTION'
	if [ "$QUEXF_BARCODE_TLX_PORTION" ]; then
        set_config 'BARCODE_TLX_PORTION' "$QUEXF_BARCODE_TLX_PORTION" 
	fi

	file_env 'QUEXF_BARCODE_BRY_PORTION'
	if [ "$QUEXF_BARCODE_BRY_PORTION" ]; then
        set_config 'BARCODE_BRY_PORTION' "$QUEXF_BARCODE_BRY_PORTION" 
	fi

	file_env 'QUEXF_BARCODE_TLY_PORTION'
	if [ "$QUEXF_BARCODE_TLY_PORTION" ]; then
        set_config 'BARCODE_TLY_PORTION' "$QUEXF_BARCODE_TLY_PORTION" 
	fi

	file_env 'QUEXF_BARCODE_BRX_PORTION'
	if [ "$QUEXF_BARCODE_BRX_PORTION" ]; then
        set_config 'BARCODE_BRX_PORTION' "$QUEXF_BARCODE_BRX_PORTION" 
	fi

	file_env 'QUEXF_BARCODE_TLX_PORTION2'
	if [ "$QUEXF_BARCODE_TLX_PORTION2" ]; then
        set_config 'BARCODE_TLX_PORTION2' "$QUEXF_BARCODE_TLX_PORTION2" 
	fi

	file_env 'QUEXF_BARCODE_BRY_PORTION2'
	if [ "$QUEXF_BARCODE_BRY_PORTION2" ]; then
        set_config 'BARCODE_BRY_PORTION2' "$QUEXF_BARCODE_BRY_PORTION2" 
	fi

	file_env 'QUEXF_BARCODE_TLY_PORTION2'
	if [ "$QUEXF_BARCODE_TLY_PORTION2" ]; then
        set_config 'BARCODE_TLY_PORTION2' "$QUEXF_BARCODE_TLY_PORTION2" 
	fi

	file_env 'QUEXF_BARCODE_BRX_PORTION2'
	if [ "$QUEXF_BARCODE_BRX_PORTION2" ]; then
        set_config 'BARCODE_BRX_PORTION2' "$QUEXF_BARCODE_BRX_PORTION2" 
	fi

    file_env 'QUEXF_DISPLAY_PAGE_WIDTH'
	if [ "$QUEXF_DISPLAY_PAGE_WIDTH" ]; then
        set_config 'DISPLAY_PAGE_WIDTH' "$QUEXF_DISPLAY_PAGE_WIDTH" 
	fi

    file_env 'QUEXF_MULTIPLE_CHOICE_MIN_FILLED'
	if [ "$QUEXF_MULTIPLE_CHOICE_MIN_FILLED" ]; then
        set_config 'MULTIPLE_CHOICE_MIN_FILLED' "$QUEXF_MULTIPLE_CHOICE_MIN_FILLED" 
	fi

    file_env 'QUEXF_MULTIPLE_CHOICE_MAX_FILLED'
	if [ "$QUEXF_MULTIPLE_CHOICE_MAX_FILLED" ]; then
        set_config 'MULTIPLE_CHOICE_MAX_FILLED' "$QUEXF_MULTIPLE_CHOICE_MAX_FILLED" 
	fi

    file_env 'QUEXF_SINGLE_CHOICE_MIN_FILLED'
	if [ "$QUEXF_SINGLE_CHOICE_MIN_FILLED" ]; then
        set_config 'SINGLE_CHOICE_MIN_FILLED' "$QUEXF_SINGLE_CHOICE_MIN_FILLED" 
	fi

    file_env 'QUEXF_SINGLE_CHOICE_MAX_FILLED'
	if [ "$QUEXF_SINGLE_CHOICE_MAX_FILLED" ]; then
        set_config 'SINGLE_CHOICE_MAX_FILLED' "$QUEXF_SINGLE_CHOICE_MAX_FILLED" 
	fi

    file_env 'QUEXF_HTPASSWD_PATH'
	if [ "$QUEXF_HTPASSWD_PATH" ]; then
        set_config 'HTPASSWD_PATH' "$QUEXF_HTPASSWD_PATH" 
	fi

    file_env 'QUEXF_HTGROUP_PATH'
	if [ "$QUEXF_HTGROUP_PATH" ]; then
        set_config 'HTGROUP_PATH' "$QUEXF_HTGROUP_PATH" 
	fi

	file_env 'MYSQL_SSL_CA' ''
	if [ "$MYSQL_SSL_CA" ]; then
        set_config 'DB_SSL' "$MYSQL_SSL_CA" 
	fi



	TERM=dumb php -- "$QUEXF_DB_HOST" "$QUEXF_DB_USER" "$QUEXF_DB_PASSWORD" "$QUEXF_DB_NAME" "$MYSQL_SSL_CA" <<'EOPHP'
<?php
// database might not exist, so let's try creating it (just to be safe)

$stderr = fopen('php://stderr', 'w');

$host = $argv[1];
$socket = null;
if (str_contains($host, ':')) {
    list($host, $socket) = explode(':', $argv[1], 2);
}
$port = 0;
if (is_numeric($socket)) {
	$port = (int) $socket;
	$socket = null;
}

$mysql = false;
do {
    $con = mysqli_init();
    if (isset($argv[5]) && !empty($argv[5])) {
	    mysqli_ssl_set($con,NULL,NULL,$argv[5],NULL,NULL);
    }
    try {
           $mysql = mysqli_real_connect($con,$host, $argv[2], $argv[3], '', $port, $socket, MYSQLI_CLIENT_SSL_DONT_VERIFY_SERVER_CERT);
       } catch (Exception $e) {
          fwrite($stderr, $e->getMessage() . " - Trying again in 3 seconds\n");
          sleep(3);
    }
} while (!$mysql);

try {
       $con->query('CREATE DATABASE IF NOT EXISTS `' . $con->real_escape_string($argv[4]) . '`');
} catch (Exception $e) {
        fwrite($stderr, "\n" . 'MySQL "CREATE DATABASE" Error: ' . $con->error . "\n");
        $con->close();
        exit(1);
}

// check if database populated
$con->select_db($con->real_escape_string($argv[4]));


$dbpop = true;
try {
   $con->query('SELECT COUNT(*) AS C FROM ' . $con->real_escape_string($argv[4]) . '.boxgrouptypes');
} catch (Exception $e) {
    fwrite($stderr, "\n" . 'Cannot find queXF database. Will now populate... ' . $con->error . "\n");

    $command = 'mysql'
        . ' --host=' . $host
        . ' --user=' . $argv[2]
        . ' --password=' . $argv[3]
        . ' --database=' . $argv[4]
        . ' --ssl-ca=' . $argv[5]
        . ' --execute="SOURCE ';

    fwrite($stderr, "\n" . 'Loading queXF database...' . "\n");
    $output1 = shell_exec($command . '/var/www/html/database/quexf.sql"');
    fwrite($stderr, "\n" . 'Loaded queXF database: ' . $output1 . "\n");

    $con->query("INSERT INTO " . $argv[4] . ".verifiers (description,http_username) VALUES ('Administrator','admin')");
	
}

if ($dbpop) {
    fwrite($stderr, "\n" . 'queXS Database found. Leaving unchanged.' . "\n");
}


$con->close();
EOPHP

#Run import process

sleep 10

su -s /bin/bash -c "php /var/www/html/admin/startprocess.php /forms" www-data &

fi

exec "$@"
