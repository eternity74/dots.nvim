
return {
  ["Edit<->Build workflow"] = {
    strategy = "workflow",
    description = "Use a workflow to repeatedly edit then build code",
    opts = {
      index = 5,
      is_default = true,
      short_name = "eb",
    },
    prompts = {
      {
        {
          name = "Fix compiler error",
          role = "user",
          opts = { auto_submit = false },
          content = function()
            -- Leverage YOLO mode which disables the requirement of approvals and automatically saves any edited buffer
            local approvals = require("codecompanion.interactions.chat.tools.approvals")
            approvals:toggle_yolo_mode()

              return [[### Instructions

Your instructions here

### Steps to Follow

You are required to write code following the instructions provided above and build the correctness by running the designated build command. Follow these steps exactly:

1. Update the code in files under current directory using the @{agent} tool
2. Then use the @{run_command} `mm` including flag argument 'build' to build the project (do this after you have updated the code)
3. Make sure you trigger both tools in the same response

We'll repeat this cycle until the build is successful. Ensure no deviations from these steps.]]
          end,
        },
      },
      {
        {
          name = "Repeat On Failure",
          role = "user",
          opts = { auto_submit = true },
          -- Scope this prompt to the run_command tool
          condition = function()
            return _G.codecompanion_current_tool == "run_command"
          end,
          -- Repeat until the build pass, as indicated by the build flag
          -- which the run_command tool sets on the chat buffer
          repeat_until = function(chat)
            return chat.tool_registry.flags.build == true
          end,
          content = "The build have failed. Can you edit the files under current directory and run the build again?",
        },
      },
    },
  },
  ["my-example workflow"] = {
    strategy = "workflow",
    description = "workflow example",
    opts = {
      index = 6,
      is_default = true,
      short_name = "me",
    },
    prompts = {
      {
        {
          name = "Gerrting Started",
          role = "user",
          opts = { auto_submit = true },
          content = function()
            -- Leverage YOLO mode which disables the requirement of approvals and automatically saves any edited buffer
            local approvals = require("codecompanion.interactions.chat.tools.approvals")
            approvals:toggle_yolo_mode()

              return [[Hi]]
          end,
        },
      },
      {
        {
          name = "Response 1",
          role = "user",
          opts = { auto_submit = true },
          content = "My name is wanchang ryu, nice to meet you!",
        },
      },
      {
        {
          name = "Response 2",
          role = "user",
          opts = { auto_submit = true },
          content = "Can you help me to write pibonacci sequence in python ?",
        },
      },
    },
  },
}
