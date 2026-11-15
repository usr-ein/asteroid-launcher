.pragma library

// What the stand-in NonGraphicalFeedback was asked to play, in order: each
// {event, at}, at in ms since the epoch. One list for the whole engine: a
// scene imports this file by its path, as the stand-in does.
var plays = []

function played(event) {
    plays.push({event: event, at: Date.now()})
}
