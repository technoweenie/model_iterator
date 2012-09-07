# ModelIterator

Basic library for iterating through large ActiveRecord datasets.  For instance,
let's say you add a new feature, and you need to backfill data for existing
records:

    iter = ModelIterator.new(User, :redis => $redis)
    iter.each do |user|
      backfill(user)
    end

ModelIterator selects the records in batches (100 by default), and loops
through the table filtering based on the ID.

    SELECT * FROM users WHERE id > 0 LIMIT 100
    SELECT * FROM users WHERE id > 100 LIMIT 100
    SELECT * FROM users WHERE id > 200 LIMIT 100

Each record's ID is tracked in Redis immediately after being processed.  If
jobs crash, you can fix code, and re-run from where you left off.

This code was ported from GitHub, where it's been frequently used for nearly
two years.

## Note on Patches/Pull Requests

1. Fork the project.
2. Make your feature addition or bug fix.
3. Add tests for it. This is important so I don't break it in a future version
   unintentionally.
4. Commit, do not mess with rakefile, version, or history. (if you want to have
   your own version, that is fine but bump version in a commit by itself I can
   ignore when I pull)
5. Send me a pull request. Bonus points for topic branches.

