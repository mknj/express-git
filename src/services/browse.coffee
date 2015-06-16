{assign} = require "../helpers"
mime = require "mime-types"
git = require "../ezgit"
Promise = require "bluebird"

SERVE_BLOB_DEFAULTS = max_age: 365 * 24 * 60 * 60

module.exports = (app, options) ->
	{BadRequestError, NotModified} = app.errors

	options = assign {}, SERVE_BLOB_DEFAULTS, options

	app.get "/:git_repo(.*).git/:refname(.*)?/:git_service(browse)/:type(blob|tree|commit)/:path(.*)?", (req, res, next) ->
		{cleanup, repo} = req.git
		{path, type, refname} = req.params
		etag = req.headers["if-none-match"]
		repo.then (repo) ->
			if refname
				repo.getReference refname
			else
				repo.head()
		.then cleanup
		.then (ref) ->
			if type is "commit" and "#{ref.target()}" is etag
				throw new NotModified()
			ref
		.then (ref) -> repo.getCommit ref.target()
		.then cleanup
		.then (commit) ->
			if type is "commit"
				commit
			else if not path and type is "tree"
				if "#{commit.treeId()}" is etag
					throw new NotModified()
				commit.getTree()
				.then cleanup
			else if path
				commit.getEntry path
				.then cleanup
				.then (entry) ->
					if type is "tree"
						unless entry.isTree()
							throw new BadRequestError
						if etag is "#{entry.oid()}"
							throw new NotModified
						entry.getTree().then cleanup
					else if type is "blob"
						unless entry.isBlob()
							throw new BadRequestError
						if etag is "#{entry.oid()}"
							throw new NotModified
						entry.getBlob().then cleanup
					else
						throw new BadRequestError
			else
				throw new BadRequestError
		.then (obj) ->
			res.set
				"Etag": "#{obj.id()}"
				"Cache-Control": "private, max-age=#{options.max_age}, no-transform, must-revalidate"
			res.json obj
		.then -> next()
		.catch next