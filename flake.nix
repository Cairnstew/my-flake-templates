{
  outputs =
    { ... }:
    {
      templates.python313 = {
        path = ./python313;
        description = "Python 3.13 development template";
      };
      templates.python314 = {
        path = ./python314;
        description = "Python 3.14 development template";
      };
    };
}
