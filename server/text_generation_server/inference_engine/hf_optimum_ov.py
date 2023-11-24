import json
import os
import time
from pathlib import Path
from typing import Any, Optional, Union

import torch
from openvino.runtime import get_version
from optimum.intel import OVModelForCausalLM, OVModelForSeq2SeqLM
from optimum.intel.version import __version__
from text_generation_server.inference_engine.engine import BaseInferenceEngine
from text_generation_server.utils.hub import TRUST_REMOTE_CODE
from transformers import AutoModelForCausalLM, AutoModelForSeq2SeqLM
from huggingface_hub import HfApi

class InferenceEngine(BaseInferenceEngine):
    def __init__(
        self,
        model_path: str,
        model_class: Union[AutoModelForCausalLM, AutoModelForSeq2SeqLM],
        dtype: torch.dtype,
        quantize: Optional[str],
        model_config: Optional[Any],
    ) -> None:
        super().__init__(model_path, model_config)
        print(f"Optimum Intel version: {__version__}")
        print(f"OpenVINO version: {get_version()}")
        print("model_path:", model_path)

        if model_class == AutoModelForCausalLM:
            model_class = OVModelForCausalLM
        elif model_class == AutoModelForSeq2SeqLM:
            model_class = OVModelForSeq2SeqLM

        ov_config_file = os.getenv("OPENVINO_CONFIG")
        if ov_config_file is not None:
            ov_config = json.loads(Path(ov_config_file).read_text())
        else:
           ov_config = None

        print(f"ov_config: {ov_config}")

        kwargs = {
            "model_id": model_path,
            "local_files_only": True,
            "trust_remote_code": TRUST_REMOTE_CODE,
            "export": False,
            "ov_config": ov_config
        }

        model_is_ov = any(f.endswith("openvino_model.xml") for f in os.listdir(model_path))

        if model_is_ov:
            print("Loading IR model directly")
            load_start = time.time()
            self.model = model_class.from_pretrained(**kwargs)
            print(f"Load of IR model took {time.time() - load_start:.3f}s")

        else:
            # Note it's currently not supported for both of these to be true - optimization will fail
            print("Converting transformers model to OpenVINO")
            kwargs["export"] = True

            convert_start = time.time()
            self.model = model_class.from_pretrained(**kwargs)
            print(
                f"Conversion to OpenVINO and initial loading took {time.time() - convert_start:.3f}s"
            )

        # For debugging
        for k,v in self.model.request.get_compiled_model().get_property("SUPPORTED_PROPERTIES").items():
            print(k, self.model.request.get_compiled_model().get_property(k))

