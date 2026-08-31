locals {
  managed_login_branding_settings = jsonencode({
    categories = {
      auth = {
        authMethodOrder = [[
          { display = "INPUT", type = "USERNAME_PASSWORD" }
        ]]
        federation = {
          interfaceStyle = "BUTTON_LIST"
          order          = []
        }
      }
      form = {
        displayGraphics     = true
        instructions        = { enabled = false }
        languageSelector    = { enabled = true }
        location            = { horizontal = "CENTER", vertical = "CENTER" }
        sessionTimerDisplay = "NONE"
      }
      global = {
        colorSchemeMode = "LIGHT"
        pageFooter      = { enabled = false }
        pageHeader      = { enabled = false }
        spacingDensity  = "REGULAR"
      }
      signUp = {
        acceptanceElements = [{ enforcement = "NONE", textKey = "en" }]
      }
    }
    componentClasses = {
      buttons    = { borderRadius = 8.0 }
      divider    = { lightMode = { borderColor = "d4d4d4ff" } }
      dropDown = {
        borderRadius = 8.0
        lightMode = {
          defaults = { itemBackgroundColor = "ffffffff" }
          hover    = { itemBackgroundColor = "f0f7f5ff", itemBorderColor = "0a7463ff", itemTextColor = "000716ff" }
          match    = { itemBackgroundColor = "e0eeebff", itemTextColor = "0a7463ff" }
        }
      }
      focusState       = { lightMode = { borderColor = "0a7463ff" } }
      idpButtons       = { icons = { enabled = true } }
      input = {
        borderRadius = 8.0
        lightMode = {
          defaults         = { backgroundColor = "ffffffff", borderColor = "7d8998ff" }
          placeholderColor = "5f6b7aff"
        }
      }
      inputDescription = { lightMode = { textColor = "5f6b7aff" } }
      inputLabel       = { lightMode = { textColor = "000716ff" } }
      link = {
        lightMode = {
          defaults = { textColor = "0a7463ff" }
          hover    = { textColor = "085e50ff" }
        }
      }
      optionControls = {
        lightMode = {
          defaults = { backgroundColor = "ffffffff", borderColor = "7d8998ff" }
          selected = { backgroundColor = "0a7463ff", foregroundColor = "ffffffff" }
        }
      }
      statusIndicator = {
        lightMode = {
          error   = { backgroundColor = "fff7f7ff", borderColor = "d91515ff", indicatorColor = "d91515ff" }
          pending = { indicatorColor = "aaaaaaaa" }
          success = { backgroundColor = "f2fcf3ff", borderColor = "037f0cff", indicatorColor = "037f0cff" }
          warning = { backgroundColor = "fffce9ff", borderColor = "8d6605ff", indicatorColor = "8d6605ff" }
        }
      }
    }
    components = {
      alert = {
        borderRadius = 12.0
        lightMode    = { error = { backgroundColor = "fff7f7ff", borderColor = "d91515ff" } }
      }
      favicon = { enabledTypes = ["ICO", "SVG"] }
      form = {
        backgroundImage = { enabled = false }
        borderRadius    = 8.0
        lightMode       = { backgroundColor = "ffffffff", borderColor = "c6c6cdff" }
        logo            = { enabled = false, formInclusion = "IN", location = "CENTER", position = "TOP" }
      }
      idpButton = {
        custom   = {}
        standard = {
          lightMode = {
            active   = { backgroundColor = "e0eeebff", borderColor = "085e50ff", textColor = "085e50ff" }
            defaults = { backgroundColor = "ffffffff", borderColor = "424650ff", textColor = "424650ff" }
            hover    = { backgroundColor = "f0f7f5ff", borderColor = "085e50ff", textColor = "085e50ff" }
          }
        }
      }
      pageBackground = {
        image     = { enabled = false }
        lightMode = { color = "f5f5f5ff" }
      }
      pageFooter = {
        backgroundImage = { enabled = false }
        lightMode       = { background = { color = "fafafaff" }, borderColor = "d5dbdbff" }
        logo            = { enabled = false, location = "START" }
      }
      pageHeader = {
        backgroundImage = { enabled = false }
        lightMode       = { background = { color = "fafafaff" }, borderColor = "d5dbdbff" }
        logo            = { enabled = false, location = "START" }
      }
      pageText = {
        lightMode = { bodyColor = "414d5cff", descriptionColor = "414d5cff", headingColor = "000716ff" }
      }
      phoneNumberSelector = { displayType = "TEXT" }
      primaryButton = {
        lightMode = {
          active   = { backgroundColor = "085e50ff", textColor = "ffffffff" }
          defaults = { backgroundColor = "0a7463ff", textColor = "ffffffff" }
          disabled = { backgroundColor = "ffffffff", borderColor = "ffffffff" }
          hover    = { backgroundColor = "085e50ff", textColor = "ffffffff" }
        }
      }
      secondaryButton = {
        lightMode = {
          active   = { backgroundColor = "e0eeebff", borderColor = "085e50ff", textColor = "085e50ff" }
          defaults = { backgroundColor = "ffffffff", borderColor = "0a7463ff", textColor = "0a7463ff" }
          hover    = { backgroundColor = "f0f7f5ff", borderColor = "085e50ff", textColor = "085e50ff" }
        }
      }
    }
  })
}
