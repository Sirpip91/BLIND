extends Resource

## What a mask leaves in the sword: a colour, and one thing it can do.

enum Power {
	## Blows coming from outside the view are felt.
	SENSE,
	## A cut off a full blade can't be stopped.
	SUNDER,
	## A perfect parry closes a wound.
	MEND,
	## Whoever's blow is slipped at the last moment is left standing in it.
	STILL,
}

@export var label := ""
@export var power := Power.SENSE
@export var color := Color(0.08, 0.3, 0.85)
@export_multiline var says := ""
