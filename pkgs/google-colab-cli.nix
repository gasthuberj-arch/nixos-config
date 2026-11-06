{
  lib,
  python3Packages,
  fetchPypi,
}: let
  # google-colab-cli requires filelock.ReadWriteLock (added in filelock >= 3.29.2).
  filelock = python3Packages.buildPythonPackage rec {
    pname = "filelock";
    version = "3.29.2";
    format = "wheel";

    src = fetchPypi {
      inherit pname version;
      format = "wheel";
      dist = "py3";
      python = "py3";
      hash = "sha256-9dP+tEsriCSDJYdUOvUiaCL+hrrwhmeO3keqF3/kfKU=";
    };

    pythonImportsCheck = ["filelock"];
  };

  jupyter-mimetypes = python3Packages.buildPythonPackage rec {
    pname = "jupyter-mimetypes";
    version = "0.2.0";
    format = "wheel";

    src = fetchPypi {
      pname = "jupyter_mimetypes";
      inherit version;
      format = "wheel";
      dist = "py3";
      python = "py3";
      hash = "sha256-5tzZiSWOP8lENltlbZFzGRUX4OOTvYeOl85QDls4hSc=";
    };

    dependencies = with python3Packages; [
      pyarrow
      typing-extensions
    ];

    pythonImportsCheck = ["jupyter_mimetypes"];
  };

  jupyter-kernel-client = python3Packages.buildPythonPackage rec {
    pname = "jupyter-kernel-client";
    version = "0.9.0";
    format = "wheel";

    src = fetchPypi {
      pname = "jupyter_kernel_client";
      inherit version;
      format = "wheel";
      dist = "py3";
      python = "py3";
      hash = "sha256-d6y48vc42XYl1r0B7ozyHE1ZeQt7pGQQhxLbOHBBbyA=";
    };

    dependencies = with python3Packages; [
      jupyter-client
      jupyter-core
      jupyter-mimetypes
      requests
      traitlets
      typing-extensions
      websocket-client
    ];

    pythonImportsCheck = ["jupyter_kernel_client"];
  };
in
  python3Packages.buildPythonApplication rec {
    pname = "google-colab-cli";
    version = "0.7.5";
    format = "wheel";

    src = fetchPypi {
      pname = "google_colab_cli";
      inherit version;
      format = "wheel";
      dist = "py3";
      python = "py3";
      hash = "sha256-KzA+0h69bagp+A1QYiSmzU8OYtUG+zcxZtBqBTLlFqk=";
    };

    pythonRelaxDeps = [
      "typer"
    ];

    dependencies = with python3Packages; [
      click
      filelock
      google-auth
      google-auth-oauthlib
      html2text
      jupyter-kernel-client
      keyring
      nbformat
      packaging
      prompt-toolkit
      pydantic
      pygments
      requests
      rich
      typer
      typing-extensions
      websocket-client
    ];

    pythonImportsCheck = ["colab_cli"];

    meta = with lib; {
      description = "Official command-line interface for Google Colab";
      homepage = "https://github.com/googlecolab/google-colab-cli";
      license = licenses.asl20;
      mainProgram = "colab";
      platforms = platforms.unix;
    };
  }
