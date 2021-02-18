# commit branch hugo
git add .
git commit -m 'add new post'
git push origin hugo

# execute command hugo
hugo

# create temporary dir
HUGO_TEMP_DIR=$(mktemp -d)
cp -R public/* "$HUGO_TEMP_DIR"

# create orphan branch 'master'
git checkout master

# empty current dir
rm .git/index
git clean -fdx

# copy back contents in dir public/
cp -R "$HUGO_TEMP_DIR"/* .

# add, commit, push
git add .
# git status
git commit -m 'update blog content'
git push -u origin master

# remove temp dir
[[ -d "$HUGO_TEMP_DIR" ]] && rm -rf "$HUGO_TEMP_DIR"

# switch to branch hugo
git checkout hugo
