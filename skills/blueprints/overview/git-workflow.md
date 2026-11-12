The git-workflow plugin gives a repository one local process: a branch per change, a checked
commit, a pull request that is squash-merged, a release counted from conventional commits, and
a release branch that follows a release tag. The commands are `bash ${BU_ROOT}/app git <command>`,
and eight of them also exist as slash commands `/git:<command>`. This skill holds the process,
the rules that always hold and the table of which command does which job. Options, settings and
reasons are in the manuals it points at; the branch settings are a pushed fact, not text.
