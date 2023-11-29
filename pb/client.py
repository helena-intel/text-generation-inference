import time

import generation_pb2 as pb2
import generation_pb2_grpc as gpb2
import grpc
from google.protobuf import json_format

port = 8033
channel = grpc.insecure_channel(f"localhost:{port}")
stub = gpb2.GenerationServiceStub(channel)

# warmup inference
text = "hello world"
message = json_format.ParseDict(
    {"requests": [{"text": text}]}, pb2.BatchedGenerationRequest()
)
response = stub.Generate(message)

# prompts = ["def hello_world():", "def calculate_square_root(number):", "def add_numbers", "function add_numbers"]
prompts = ["The weather is", "The cat is walking on", "I would like to"]

# optional: parameters for inference
params = pb2.Parameters(
    method="GREEDY", stopping=pb2.StoppingCriteria(min_new_tokens=20, max_new_tokens=20)
)

# time inference
for prompt in prompts:
    message = json_format.ParseDict(
        {"requests": [{"text": prompt}]}, pb2.BatchedGenerationRequest(params=params)
    )
    start = time.perf_counter()
    response = stub.Generate(message)
    end = time.perf_counter()
    print(f"Duration: {end-start:.2f}")
    print(prompt, response)
