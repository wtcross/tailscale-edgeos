#!/bin/bash
set -o nounset
set -o errexit

TAILSCALE_ROOT="${TAILSCALE_ROOT:-/config/tailscale}"
TAILSCALE="${TAILSCALE_ROOT}/tailscale"
TAILSCALED="${TAILSCALE_ROOT}/tailscaled"
TAILSCALED_SOCK="${TAILSCALED_SOCK:-/var/run/tailscale/tailscaled.sock}"

_tailscale_fail_unless_root() {
	if [ "$(id -u)" != '0' ]; then
		log_failure_msg "must be run as root"
		exit 1
	fi
}

_tailscale_is_running() {
	if [ -e "${TAILSCALED_SOCK}" ]; then
		return 0
	else
		return 1
	fi
}

_tailscale_is_installed() {
	if [ -e "${TAILSCALE}" ] && [ -e "${TAILSCALED}" ]; then
		return 0
	else
		return 1
	fi
}

_tailscale_start() {
	source "${TAILSCALE_ROOT}/tailscale-env"

	PORT="${PORT:-41641}"
	TAILSCALE_FLAGS="${TAILSCALE_FLAGS:-""}"
	TAILSCALED_FLAGS="${TAILSCALED_FLAGS:-"--tun userspace-networking"}"
	LOG_FILE="${TAILSCALE_ROOT}/tailscaled.log"

	if _tailscale_is_running; then
		echo "Tailscaled is already running"
	else
		echo "Starting Tailscaled..."
		${TAILSCALED} --cleanup > "${LOG_FILE}" 2>&1

		# shellcheck disable=SC2086
		setsid ${TAILSCALED} \
			--state "${TAILSCALE_ROOT}/tailscaled.state" \
			--socket "${TAILSCALED_SOCK}" \
			--port "${PORT}" \
			${TAILSCALED_FLAGS} >> "${LOG_FILE}" 2>&1 &

		# Wait a few seconds for the daemon to start
		sleep 5

		if _tailscale_is_running; then
			echo "Tailscaled started successfully"
		else
			echo "Tailscaled failed to start"
			exit 1
		fi

		# Run tailscale up to configure
		echo "Running tailscale up to configure interface..."
		# shellcheck disable=SC2086
		${TAILSCALE} up ${TAILSCALE_FLAGS}
	fi
}

_tailscale_stop() {
	${TAILSCALE} down || true

	pkill tailscaled 2>/dev/null || true

	${TAILSCALED} --cleanup
}

_tailscale_install() {
	VERSION="$(curl -sSLq --ipv4 'https://pkgs.tailscale.com/stable/?mode=json' | jq -r '.Tarballs.mips64' | sed -rn 's/tailscale_(.*)_mips64.tgz/\1/p')"
	WORKDIR="$(mktemp -d || exit 1)"
	trap "rm -rf ${WORKDIR}" EXIT
	TAILSCALE_TGZ="${WORKDIR}/tailscale.tgz"

	echo "Installing Tailscale v${VERSION} in ${TAILSCALE_ROOT}..."
	curl -sSLf --ipv4 -o "${TAILSCALE_TGZ}" "https://pkgs.tailscale.com/stable/tailscale_${VERSION}_mips64.tgz" || {
		echo "Failed to download Tailscale v${VERSION} from https://pkgs.tailscale.com/stable/tailscale_${VERSION}_mips64.tgz"
		echo "Please make sure that you're using a valid version number and try again."
		exit 1
	}
	
	tar xzf "${TAILSCALE_TGZ}" -C "${WORKDIR}"
	mkdir -p "${TAILSCALE_ROOT}"
	cp -R "${WORKDIR}/tailscale_${VERSION}_mips64"/* "${TAILSCALE_ROOT}"

	ln -s ${TAILSCALE} /usr/bin/tailscale
	ln -s ${TAILSCALED} /usr/sbin/tailscaled

	cat <<- EOF > "${TAILSCALE_ROOT}/tailscale-env"
		PORT="41641"
		TAILSCALED_FLAGS="--tun userspace-networking"
		TAILSCALE_FLAGS=""
		TAILSCALE_AUTOUPDATE="true"
	EOF

	cat <<- EOF > /config/scripts/post-config.d/tailscale.sh
		#!/bin/sh
		/config/tailscale/tailscale-usg.sh post-config
	EOF
	
	echo "Installation complete, run '$0 start' to start Tailscale"
}

_tailscale_uninstall() {
	${TAILSCALED} --cleanup
	rm -f /config/scripts/post-config.d/tailscale.sh
	rm -f /usr/bin/tailscale
	rm -f /usr/sbin/tailscaled
	rm -rf ${TAILSCALE_ROOT}
}

tailscale_status() {
	if ! _tailscale_is_installed; then
		echo "Tailscale is not installed"
		exit 1
	elif _tailscale_is_running; then
		echo "Tailscaled is running"
		$TAILSCALE --version
	else
		echo "Tailscaled is not running"
	fi
}

tailscale_start() {
	_tailscale_fail_unless_root
	_tailscale_start
}

tailscale_stop() {
	_tailscale_fail_unless_root
	echo "Stopping Tailscale..."
	_tailscale_stop
}

tailscale_install() {
	_tailscale_fail_unless_root
	_tailscale_install
	
	echo "Installation complete, run '$0 start' to start Tailscale"
}

tailscale_uninstall() {
	_tailscale_fail_unless_root
	echo "Removing Tailscale"
	_tailscale_uninstall
}

tailscale_has_update() {
	CURRENT_VERSION="$($TAILSCALE --version | head -n 1)"
	TARGET_VERSION="$(curl -sSLq --ipv4 'https://pkgs.tailscale.com/stable/?mode=json' | jq -r '.Tarballs.mips64' | sed -rn 's/tailscale_(.*)_mips64.tgz/\1/p')"
	if [ "${CURRENT_VERSION}" != "${TARGET_VERSION}" ]; then
		return 0
	else
		return 1
	fi
}

tailscale_update() {
	_tailscale_fail_unless_root
	tailscale_stop
	tailscale_install
	tailscale_start
}

case $1 in
	"status")
		tailscale_status
		;;
	"start")
		tailscale_start
		;;
	"stop")
		tailscale_stop
		;;
	"restart")
		tailscale_stop
		tailscale_start
		;;
	"install-latest")
		if _tailscale_is_running; then
			echo "Tailscale is already installed and running, if you wish to update it, run '$0 update'"
			echo "If you wish to force a reinstall, run '$0 install!'"
			exit 0
		fi

		tailscale_install
		;;
	"uninstall")
		tailscale_stop
		tailscale_uninstall
		;;
	"update")
		if tailscale_has_update "$2"; then
			if _tailscale_is_running; then
				echo "Tailscaled is running, please stop it before updating"
				exit 1
			fi

			tailscale_install
		else
			echo "Tailscale is already up to date"
		fi
		;;
	"post-config")
		if ! _tailscale_is_installed; then
			tailscale_install
		fi

		# shellcheck source=package/tailscale-env
		source "${PACKAGE_ROOT}/tailscale-env"

		if [ "${TAILSCALE_AUTOUPDATE}" = "true" ]; then
			tailscale_has_update && tailscale_update || echo "Not updated"
		fi

		tailscale_start
		;;
	*)
		echo "Usage: $0 {status|start|stop|restart|install-latest|uninstall|update}"
		exit 1
		;;
esac