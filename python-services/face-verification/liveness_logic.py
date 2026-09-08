CENTER_EAR_MIN = 0.20

BLINK_CLOSED_MAX = 0.18

BLINK_REOPEN_MIN = 0.22

CENTER_YAW_MAX = 0.15

TURN_YAW_MIN = 0.30

SMILE_MAR_MIN = 0.35


def advance_liveness(
    state,
    ear,
    yaw,
    mar,
    blink_started,
):
    if state == "LOOK_CENTER":

        if (
            abs(yaw) <
            CENTER_YAW_MAX
            and
            ear >
            CENTER_EAR_MIN
        ):
            return (
                "BLINK",
                blink_started,
            )

    elif state == "BLINK":

        if ear < BLINK_CLOSED_MAX:

            return (
                "BLINK",
                True,
            )

        if (
            blink_started
            and
            ear >=
            BLINK_REOPEN_MIN
        ):
            return (
                "HEAD_TURN",
                False,
            )

    elif state == "HEAD_TURN":

        if (
            abs(yaw) >
            TURN_YAW_MIN
        ):
            return (
                "SMILE",
                blink_started,
            )

    elif state == "SMILE":

        if mar > SMILE_MAR_MIN:

            return (
                "PASSED",
                blink_started,
            )

    return (
        state,
        blink_started,
    )