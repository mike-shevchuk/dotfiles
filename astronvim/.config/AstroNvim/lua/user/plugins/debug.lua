local dap = { 
  "rcarriga/nvim-dap-ui", 
  depends = {"mfussenegger/nvim-dap"},
  config = function()
    require("dapui").setup({
      configurations = {
        {
          type = "python";
          request = "launch";
          name = "Launch file";
          program = "${file}";
          pythonPath = function()
            return '/usr/bin/python'
          end;
        }
      }
    })

  end
}

-- local dap_python = require('dap')
--     dap.configurations.python = {
--       {
--         type = 'python';
--         request = 'launch';
--         name = "Launch file";
--         program = "${file}";
--         pythonPath = function()
--           return '/usr/bin/python'
--         end;
--       },
--     }



return {dap}
