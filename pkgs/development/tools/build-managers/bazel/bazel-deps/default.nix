{ stdenv, buildBazelPackage, lib, fetchFromGitHub, git, jdk8, jre, makeWrapper }:

buildBazelPackage rec {
  name = "bazel-deps-${version}";
  version = "2018-11-01";

  meta = with stdenv.lib; {
    homepage = "https://github.com/johnynek/bazel-deps";
    description = "Generate bazel dependencies for maven artifacts";
    license = licenses.mit;
    maintainers = [ maintainers.uri-canva ];
    platforms = platforms.all;
  };

  src = fetchFromGitHub {
    owner = "johnynek";
    repo = "bazel-deps";
    rev = "1af8921d52f053fad575f26762533a3823b4a847";
    sha256 = "0srz0sbz4bq9n7cp4g1n3kd3j6rcjqfi25sq8aa64l27yqzbk53x";
  };

  bazelTarget = "//src/scala/com/github/johnynek/bazel_deps:parseproject_deploy.jar";

  buildInputs = [ git makeWrapper jdk8 ];

  fetchAttrs = {
    preInstall = ''
      # Remove all built in external workspaces, Bazel will recreate them when building
      rm -rf $bazelOut/external/{bazel_tools,\@bazel_tools.marker,embedded_jdk,\@embedded_jdk.marker,local_*,\@local_*}
      # For each external workspace, remove all files that aren't referenced by Bazel
      # Many of these files are non-hermetic (for example .git/refs/remotes/origin/HEAD)
      files_to_delete=()
      for workspace in $(find $bazelOut/external -maxdepth 2 -name "WORKSPACE" -print0 | xargs -0L1 dirname); do
        workspaceOut="$NIX_BUILD_TOP/workspaces/$(basename workspace)/output"
        workspaceUserRoot="$NIX_BUILD_TOP/workspaces/$(basename workspace)/tmp"
        rm -rf $workspace/.git
        if ! targets_and_files=$(cd "$workspace" && bazel --output_base="$workspaceOut" --output_user_root="$workspaceUserRoot" query '//...:*' 2> /dev/null | sort -u); then
          continue
        fi
        if ! targets=$(cd "$workspace" && bazel --output_base="$workspaceOut" --output_user_root="$workspaceUserRoot" query '//...:all' 2> /dev/null | sort -u); then
          continue
        fi
        mapfile -t referenced_files < <(comm -23 <(printf '%s' "$targets_and_files") <(printf '%s' "$targets") | sed -e 's,^//:,,g' | sed -e 's,^//,,g' | sed -e 's,:,/,g')
        referenced_files+=( "WORKSPACE" )
        for referenced_file in "''${referenced_files[@]}"; do
          # Some of the referenced files are symlinks to non-referenced files.
          # The symlink targets have deterministic contents, but non-deterministic
          # paths. Copy them to the referenced path, which is deterministic.
          if target=$(readlink "$workspace/$referenced_file"); then
            rm "$workspace/$referenced_file"
            cp -a "$target" "$workspace/$referenced_file"
          fi
        done
        mapfile -t workspace_files_to_delete < <(find "$workspace" -type f -or -type l | sort -u | comm -23 - <(printf "$workspace/%s\n" "''${referenced_files[@]}" | sort -u))
        for workspace_file_to_delete in "''${workspace_files_to_delete[@]}"; do
          files_to_delete+=("$workspace_file_to_delete")
        done
        # We're running bazel in many different workspaces in a loop. Letting the
        # daemon shut down on its own would leave several daemons alive at the
        # same time, using up a lot of memory. Shut them down explicitly instead.
        bazel --output_base="$workspaceOut" --output_user_root="$workspaceUserRoot" shutdown 2> /dev/null
      done
      for file_to_delete in "''${files_to_delete[@]}"; do
        rm "$file_to_delete"
      done
      find . -type d -empty -delete
    '';

    sha256 = "1gvl4a9z8p4ch2gmcj3lpp0imrkrvy8wng949p3wlkibi14hc6ww";
  };

  buildAttrs = {
    installPhase = ''
      mkdir -p $out/bin/bazel-bin/src/scala/com/github/johnynek/bazel_deps

      cp gen_maven_deps.sh $out/bin
      wrapProgram "$out/bin/gen_maven_deps.sh" --set JAVA_HOME "${jre}" --prefix PATH : ${lib.makeBinPath [ jre ]}
      cp bazel-bin/src/scala/com/github/johnynek/bazel_deps/parseproject_deploy.jar $out/bin/bazel-bin/src/scala/com/github/johnynek/bazel_deps
    '';
  };
}
