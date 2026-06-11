#!/usr/bin/env bats

load setup

# ====================== connection.sh ======================

@test "connection: rejects no arguments" {
    run "$SENDORBIT_ROOT/modules/connection.sh"
    [ "$status" -eq 1 ]
}

@test "connection: rejects one argument" {
    run "$SENDORBIT_ROOT/modules/connection.sh" "user"
    [ "$status" -eq 1 ]
}

@test "connection: rejects four arguments" {
    run "$SENDORBIT_ROOT/modules/connection.sh" "user" "host" "22" "extra"
    [ "$status" -eq 1 ]
}

@test "connection: rejects invalid user" {
    run "$SENDORBIT_ROOT/modules/connection.sh" "user-;rm" "host"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid parameters"* ]]
}

@test "connection: rejects invalid host" {
    run "$SENDORBIT_ROOT/modules/connection.sh" "user" "host;evil"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid parameters"* ]]
}

# ====================== transfer.sh ======================

@test "transfer: rejects no arguments" {
    run "$SENDORBIT_ROOT/modules/transfer.sh"
    [ "$status" -eq 1 ]
}

@test "transfer: rejects three arguments" {
    run "$SENDORBIT_ROOT/modules/transfer.sh" "scp" "user" "host"
    [ "$status" -eq 1 ]
}

@test "transfer: rejects invalid type" {
    run "$SENDORBIT_ROOT/modules/transfer.sh" "invalid" "user" "host" "22" "/dest"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid type"* ]]
}

@test "transfer: rejects invalid user" {
    run "$SENDORBIT_ROOT/modules/transfer.sh" "scp" "user-;rm" "host" "22" "/dest"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid parameters"* ]]
}

@test "transfer: rejects invalid host" {
    run "$SENDORBIT_ROOT/modules/transfer.sh" "rsync" "user" "host;evil" "22" "/dest"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid parameters"* ]]
}
