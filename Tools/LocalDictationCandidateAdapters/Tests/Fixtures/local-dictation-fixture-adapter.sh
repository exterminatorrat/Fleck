#!/bin/sh
set -eu

mode=${1:-cooperative}
fixture_marker=${2:-}
shutdown_count=0

emit() {
  printf '%s\n' "$1"
}

record_fixture_request() {
  if [ -n "$fixture_marker" ]; then
    printf '%s\n' "$1" >> "$fixture_marker"
  fi
}

while IFS= read -r line; do
  request_id=$(printf '%s' "$line" | sed -n 's/.*"requestID":"\([^"]*\)".*/\1/p')
  operation=$(printf '%s' "$line" | sed -n 's/.*"operation":"\([^"]*\)".*/\1/p')
  request_id=${request_id:-unknown}

  case "$mode:$operation" in
    malformed:*)
      emit '{malformed'
      exit 0
      ;;
    wrong-id:*)
      emit '{"event":"ready","modelRevision":"fixture","requestID":"unexpected","runtimeVersion":"fixture","schemaVersion":1}'
      exit 0
      ;;
    invalid-order:transcribe)
      emit "{\"event\":\"final\",\"requestID\":\"$request_id\",\"schemaVersion\":1,\"transcript\":\"final\"}"
      emit "{\"event\":\"partial\",\"requestID\":\"$request_id\",\"schemaVersion\":1,\"sequence\":1,\"transcript\":\"late\"}"
      ;;
    flood-both:*)
      i=0
      while [ "$i" -lt 20000 ]; do
        printf '/private/model-root/secret-diagnostic-%s\n' "$i" >&2
        i=$((i + 1))
      done
      i=0
      while [ "$i" -lt 20000 ]; do
        printf 'not-json-%s\n' "$i"
        i=$((i + 1))
      done
      exit 0
      ;;
    flood-events:load)
      i=0
      while [ "$i" -lt 512 ]; do
        emit "{\"event\":\"measurement\",\"name\":\"fixture-$i\",\"requestID\":\"$request_id\",\"schemaVersion\":1,\"unit\":\"count\",\"value\":$i}"
        i=$((i + 1))
      done
      sleep 5
      exit 0
      ;;
    flood-measurements:transcribe)
      i=0
      while [ "$i" -lt 20000 ]; do
        emit "{\"event\":\"measurement\",\"name\":\"fixture-$i\",\"requestID\":\"$request_id\",\"schemaVersion\":1,\"unit\":\"count\",\"value\":$i}"
        i=$((i + 1))
      done
      sleep 2
      exit 0
      ;;
    cancel-failure:cancel)
      emit "{\"code\":\"fixture-failure\",\"event\":\"failure\",\"message\":\"candidate failed\",\"requestID\":\"$request_id\",\"schemaVersion\":1}"
      sleep 5
      ;;
    shutdown-failure:shutdown)
      emit "{\"code\":\"fixture-failure\",\"event\":\"failure\",\"message\":\"candidate failed\",\"requestID\":\"$request_id\",\"schemaVersion\":1}"
      sleep 5
      ;;
    cancel-wrong-terminal:cancel)
      emit "{\"event\":\"unloaded\",\"requestID\":\"$request_id\",\"schemaVersion\":1}"
      ;;
    cancel-timeout-shutdown-forced:transcribe)
      ;;
    cancel-timeout-shutdown-forced:cancel)
      ;;
    cancel-timeout-shutdown-forced:shutdown)
      emit "{\"event\":\"unloaded\",\"requestID\":\"$request_id\",\"schemaVersion\":1}"
      sleep 5
      ;;
    cancel-ack-then-malformed:transcribe)
      ;;
    cancel-ack-then-malformed:cancel)
      printf '%s\n%s\n' "{\"event\":\"cancelled\",\"requestID\":\"$request_id\",\"schemaVersion\":1}" '{malformed'
      ;;
    shutdown-ack-then-malformed:shutdown)
      printf '%s\n%s\n' "{\"event\":\"unloaded\",\"requestID\":\"$request_id\",\"schemaVersion\":1}" '{malformed'
      ;;
    shutdown-delayed-malformed:shutdown)
      emit "{\"event\":\"unloaded\",\"requestID\":\"$request_id\",\"schemaVersion\":1}"
      sleep 0.05
      emit '{malformed'
      sleep 5
      ;;
    shutdown-nonzero-after-ack:shutdown)
      emit "{\"event\":\"unloaded\",\"requestID\":\"$request_id\",\"schemaVersion\":1}"
      exit 7
      ;;
    concurrent-shutdown-delayed-malformed:shutdown)
      shutdown_count=$((shutdown_count + 1))
      record_fixture_request shutdown
      if [ "$shutdown_count" -eq 1 ]; then
        emit "{\"event\":\"unloaded\",\"requestID\":\"$request_id\",\"schemaVersion\":1}"
        (
          sleep 0.05
          emit '{malformed'
          sleep 5
        ) &
      else
        emit "{\"event\":\"unloaded\",\"requestID\":\"$request_id\",\"schemaVersion\":1}"
      fi
      ;;
    completed-load-cancel-probe:load)
      emit "{\"event\":\"ready\",\"modelRevision\":\"fixture\",\"requestID\":\"$request_id\",\"runtimeVersion\":\"fixture\",\"schemaVersion\":1}"
      ;;
    completed-load-cancel-probe:cancel)
      exit 17
      ;;
    cooperative-cancel:transcribe)
      emit "{\"event\":\"partial\",\"requestID\":\"$request_id\",\"schemaVersion\":1,\"sequence\":1,\"transcript\":\"partial\"}"
      ;;
    cooperative-cancel:cancel)
      emit "{\"event\":\"cancelled\",\"requestID\":\"$request_id\",\"schemaVersion\":1}"
      ;;
    cancel-after-final:transcribe)
      ;;
    cancel-after-final:cancel)
      target_request_id=$(printf '%s' "$line" | sed -n 's/.*"targetRequestID":"\([^"]*\)".*/\1/p')
      target_request_id=${target_request_id:-unknown}
      emit "{\"event\":\"final\",\"requestID\":\"$target_request_id\",\"schemaVersion\":1,\"transcript\":\"final-before-cancel\"}"
      emit "{\"event\":\"cancelled\",\"requestID\":\"$request_id\",\"schemaVersion\":1}"
      ;;
    failure:transcribe)
      emit "{\"code\":\"fixture-failure\",\"event\":\"failure\",\"message\":\"candidate failed\",\"requestID\":\"$request_id\",\"schemaVersion\":1}"
      sleep 5
      ;;
    silent:transcribe)
      sleep 5
      ;;
    stuck:load)
      emit "{\"event\":\"ready\",\"modelRevision\":\"fixture\",\"requestID\":\"$request_id\",\"runtimeVersion\":\"fixture\",\"schemaVersion\":1}"
      ;;
    stuck:transcribe)
      while :; do :; done
      ;;
    stuck:*)
      while :; do :; done
      ;;
    eof-before-shutdown:shutdown)
      exit 0
      ;;
    *:load)
      emit "{\"event\":\"ready\",\"modelRevision\":\"fixture\",\"requestID\":\"$request_id\",\"runtimeVersion\":\"fixture\",\"schemaVersion\":1}"
      ;;
    *:transcribe)
      emit "{\"event\":\"partial\",\"requestID\":\"$request_id\",\"schemaVersion\":1,\"sequence\":1,\"transcript\":\"partial\"}"
      if [ "$mode" = "cooperative" ]; then
        sleep 0.1
      fi
      emit "{\"event\":\"final\",\"requestID\":\"$request_id\",\"schemaVersion\":1,\"transcript\":\"final\"}"
      ;;
    *:clean)
      emit "{\"event\":\"final\",\"requestID\":\"$request_id\",\"schemaVersion\":1,\"transcript\":\"cleaned\"}"
      ;;
    *:cancel)
      emit "{\"event\":\"cancelled\",\"requestID\":\"$request_id\",\"schemaVersion\":1}"
      ;;
    *:unload|*:shutdown)
      emit "{\"event\":\"unloaded\",\"requestID\":\"$request_id\",\"schemaVersion\":1}"
      if [ "$operation" = "shutdown" ]; then
        exit 0
      fi
      ;;
  esac
done
