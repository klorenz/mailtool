makeSequence = (numbers) ->
  if numbers instanceof Array
    sequence = []
    numbers.sort()
    start = null
    last = null

    pushSequence = ->
      if last == start
        sequence.push start
      else
        sequence.push "#{start}:#{last}"

    for num in numbers
      unless start?
        start = last = num
        continue

      unless num == last + 1
        pushSequence()
        start = last = num
        continue

      last = num

    pushSequence()

    return sequence.join ","

  return numbers

module.exports = {makeSequence}
